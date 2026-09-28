import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:harness/terminal/terminal_text.dart';

import '../core/models.dart';
import '../logging/app_log.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/skeleton.dart';
import '../state/app_state.dart';
import '../state/terminal_pane.dart';
import '../terminal/terminal_binary.dart';
import '../terminal/terminal_session.dart';
import '../widgets/terminal_panel.dart';
import '../ws/ws_conn.dart';
import '../viewer/observer_relay_codec.dart';
import '../widgets/terminal_text_action.dart';
import 'harness_comments.dart';

class SharedHarnessPanel extends StatefulWidget {
  const SharedHarnessPanel({
    super.key,
    required this.notifier,
    required this.pane,
    required this.grant,
    required this.hasAccess,
    required this.visible,
    required this.onClose,
    this.link = false,
    this.linkEnvironment,
    this.onSignIn,
  });
  final AppNotifier notifier;
  final TerminalPane pane;
  final SharedHarness grant;
  final bool hasAccess, visible;
  final VoidCallback onClose;
  final bool link;
  final String? linkEnvironment;
  final VoidCallback? onSignIn;
  @override
  State<SharedHarnessPanel> createState() => _SharedHarnessPanelState();
}

class _SharedHarnessPanelState extends State<SharedHarnessPanel> {
  late WsConn _connection;
  late TerminalSession _terminal;
  ConnectionStatus _status = ConnectionStatus.connecting;
  String? _failure;
  String _viewerMessage = 'Waiting for the live viewer…';
  Uint8List? _image;
  bool _viewerSelected = false, _ended = false;

  /// The person picked Terminal or Viewer themselves. Until they do, the first
  /// live frame brings the viewer forward on a narrow pane — a shared Blender
  /// or Marp harness was shared for what it shows, and a "Viewer" tab nobody
  /// noticed left the person looking at a terminal they cannot type into
  /// (owner, 2026-09-18: "chỉ thấy màn hình terminal").
  bool _viewerChosen = false;
  String _lastViewerState = '';
  int _generation = 0;
  bool _commentsSelected = false, _commentsOpened = false;
  final _commentUpdates = ValueNotifier<int>(0);
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final generation = ++_generation;
    final viewer = widget.notifier.viewer;
    final uri = Uri.parse(widget.notifier.config.localCliBaseUrl)
        .replace(scheme: 'ws', path: '/api/local-ws');
    _terminal = TerminalSession(
      machineId: widget.pane.machineId,
      agentId: widget.grant.agentId,
      agentName: widget.grant.name,
      engineId: widget.grant.engine,
      readOnly: true,
      send: (type, payload) => _connection.sendTerminalFrame(type, payload),
      sendBinary: (_) async => false,
      onOpenStalled: () => _connection.forceReconnect(),
      resyncTimeout: const Duration(seconds: 15),
    );
    _connection = WsConn(
      wsBaseUrl: widget.notifier.config.wsBaseUrl,
      autonomousEnv:
          widget.linkEnvironment ?? widget.notifier.config.autonomousEnv,
      machineId: widget.pane.machineId,
      observerShareId: widget.grant.id,
      observerLink: widget.link,
      transportKind: viewer == null
          ? WsTransportKind.localPlaintext
          : WsTransportKind.cloudE2ee,
      localWsUri: uri,
      localTransport: viewer == null
          ? widget.notifier.localDaemonTransport
          : null,
      accessTokenProvider: (force, failedToken) async => viewer == null
          ? ''
          : widget.link && !await viewer.auth.hasSession()
          ? ''
          : viewer.auth.accessToken(force: force, failedToken: failedToken),
      relayCodecs: viewer == null
          ? null
          : (_) async {
              final owner = widget.grant.ownerPublicKey;
              if (owner == null || owner.isEmpty) return null;
              return ObserverRelayCodec.create(
                machineId: widget.pane.machineId,
                shareId: widget.grant.id,
                ownerPublicKey: owner,
              );
            },
      onAuthFailure: (reason) {
        if (generation == _generation) _end(reason);
      },
      onLocalFailure: (code, reason) {
        if (generation == _generation) _end(reason);
      },
      onEvent: (frame) async {
        if (generation != _generation) return;
        final type = frame['type'] as String,
            payload = Map<String, dynamic>.from(frame['payload'] as Map);
        if (type == 'observer_viewer') {
          if (!mounted || _ended) {
            appLog.warn(
              'share',
              'pane ${widget.pane.id} dropped viewer frame ${payload['state']} (mounted=$mounted ended=$_ended)',
            );
            return;
          }
          Uint8List? next;
          try {
            if (payload['data'] is String) {
              next = base64Decode(payload['data'] as String);
            }
          } on FormatException catch (error) {
            appLog.warn(
              'share',
              'pane ${widget.pane.id} viewer frame did not decode: $error',
            );
            return;
          }
          // On change only: live frames come 2–3 a second, and a line per frame
          // would bury the one that matters — the first, and every refusal.
          final state = '${payload['state']}';
          if (state != _lastViewerState) {
            _lastViewerState = state;
            appLog.debug(
              'share',
              'pane ${widget.pane.id} viewer $state bytes=${next?.length ?? 0}'
                  '${payload['message'] != null ? ' · ${payload['message']}' : ''}',
            );
          }
          setState(() {
            if (next != null) {
              if (_image == null && !_viewerChosen) _viewerSelected = true;
              _image = next;
            }
            _viewerMessage =
                payload['message'] as String? ??
                (payload['state'] == 'live'
                    ? 'Live viewer'
                    : 'Opening the viewer…');
          });
        } else if (type == 'observer_comments') {
          _commentUpdates.value++;
        } else {
          await _terminal.handleFrame(type, payload);
        }
      },
      onStatus: (status) {
        if (!mounted || _ended || generation != _generation) return;
        setState(() {
          _status = status;
          _failure = null;
        });
        if (status == ConnectionStatus.connected) {
          unawaited(_terminal.reopen());
          unawaited(
            _connection.sendTerminalFrame('observer_viewer', {
              'agentId': widget.grant.agentId,
            }),
          );
        } else {
          _terminal.transportLost('Waiting for the owner to reconnect.');
        }
      },
    );
    _connection.onBinaryFrame = (bytes) async {
      if (generation != _generation) return;
      final frame = decodeTerminalLocal(bytes);
      if (frame != null && !_ended) await _terminal.handleBinary(frame);
    };
    if (widget.hasAccess) {
      unawaited(_connection.connect());
    } else {
      _ended = true;
      _failure = 'Access removed or invitation expired.';
    }
  }

  void _end(String reason) {
    if (!mounted || _ended) return;
    setState(() {
      _ended = true;
      _failure = reason;
      _image = null;
    });
    _terminal.transportLost(reason);
    unawaited(_connection.close());
  }

  @override
  void didUpdateWidget(SharedHarnessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hasAccess && !_ended) {
      _end('Access removed or invitation expired.');
    } else if (widget.hasAccess &&
        (!oldWidget.hasAccess ||
            widget.grant.id != oldWidget.grant.id ||
            widget.grant.ownerPublicKey != oldWidget.grant.ownerPublicKey)) {
      unawaited(_connection.close());
      _terminal.dispose();
      _ended = false;
      _failure = null;
      _image = null;
      _status = ConnectionStatus.connecting;
      _start();
    }
  }

  @override
  void dispose() {
    unawaited(_connection.close());
    _terminal.dispose();
    _commentUpdates.dispose();
    super.dispose();
  }

  void _retry() {
    unawaited(_connection.close());
    _terminal.dispose();
    _ended = false;
    _failure = null;
    _status = ConnectionStatus.connecting;
    setState(_start);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    TerminalFontScope.watch(context);
    final live = !_ended && _status == ConnectionStatus.connected;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: grid.AppSurface.recess,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.grant.name,
                      overflow: TextOverflow.ellipsis,
                      style: terminalContentStyle().copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('View only', style: terminalContentStyle()),
                  IconButton(
                    tooltip: 'Close shared harness',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _ended
                          ? 'Sharing ended'
                          : live
                          ? 'Live'
                          : 'Reconnecting',
                      style: terminalContentStyle(
                        color: grid.AppPalette.textSecondary,
                      ),
                    ),
                  ),
                  if (_ended && widget.hasAccess)
                    TerminalTextAction(label: 'Retry', onPressed: _retry),
                  TerminalTextAction(
                    label: _commentsSelected ? 'Watch' : 'Comments',
                    onPressed: () => setState(() {
                      _commentsSelected = !_commentsSelected;
                      _commentsOpened = true;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_failure != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: grid.AppSurface.recess,
            child: Text(_failure!, style: grid.AppType.body()),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, size) {
              final wide = size.maxWidth >= 1000;
              final commentsWidth = wide
                  ? (terminalCellSizeOf(context).width * 44).clamp(
                      280.0,
                      size.maxWidth * .45,
                    )
                  : size.maxWidth;
              return Stack(
                children: [
                  Positioned.fill(
                    right: _commentsSelected && wide ? commentsWidth : 0,
                    child: Offstage(
                      offstage: _commentsSelected && !wide,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          Widget terminal() => TerminalPanel(
                            notifier: widget.notifier,
                            session: _terminal,
                            focused: widget.notifier.isPaneFocused(
                              widget.pane.id,
                            ),
                            visible: widget.visible,
                            showHeader: false,
                            readOnly: true,
                            viewportSize: constraints.biggest,
                          );
                          Widget viewer() => ColoredBox(
                            color: grid.AppPalette.windowBg,
                            child: Center(
                              child: _image == null
                                  ? Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!_ended)
                                            const Skeleton(
                                              width: 220,
                                              height: 130,
                                            ),
                                          const SizedBox(height: 14),
                                          Text(
                                            _viewerMessage,
                                            textAlign: TextAlign.center,
                                            style: grid.AppType.body(
                                              color:
                                                  grid.AppPalette.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Image.memory(
                                      _image!,
                                      gaplessPlayback: true,
                                      fit: BoxFit.contain,
                                      semanticLabel:
                                          'Live output from ${widget.grant.name}',
                                      errorBuilder: (_, _, _) => const Text(
                                        'Waiting for the next viewer frame.',
                                      ),
                                    ),
                            ),
                          );
                          if (constraints.maxWidth >= 880) {
                            return Row(
                              children: [
                                Expanded(flex: 5, child: terminal()),
                                VerticalDivider(
                                  width: 1,
                                  color: grid.AppPalette.textFaint,
                                ),
                                Expanded(flex: 4, child: viewer()),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _viewerChosen = true;
                                      _viewerSelected = false;
                                    }),
                                    child: Text(
                                      'Terminal',
                                      style: TextStyle(
                                        fontWeight: !_viewerSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _viewerChosen = true;
                                      _viewerSelected = true;
                                    }),
                                    child: Text(
                                      'Viewer',
                                      style: TextStyle(
                                        fontWeight: _viewerSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Flexible(
                                    child: Text(
                                      widget.pane.sharedOwnerName ??
                                          'Shared harness',
                                      overflow: TextOverflow.ellipsis,
                                      style: grid.AppType.monoLabel(
                                        fontWeight: grid.AppFont.regular,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                              ),
                              Expanded(
                                child: IndexedStack(
                                  index: _viewerSelected ? 1 : 0,
                                  children: [terminal(), viewer()],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (_commentsOpened)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: commentsWidth,
                      child: Offstage(
                        offstage: !_commentsSelected,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: grid.AppPalette.windowBg,
                            border: Border(
                              left: BorderSide(color: grid.AppPalette.divider),
                            ),
                          ),
                          child: HarnessComments(
                            updates: _commentUpdates,
                            onSignIn: widget.onSignIn,
                            manage: (action, payload) => _connection.request(
                              'observer_$action',
                              payload: {
                                'agentId': widget.grant.agentId,
                                ...payload,
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
