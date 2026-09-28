import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';
import '../widgets/box_chrome.dart';
import '../widgets/terminal_prompt.dart';
import '../widgets/terminal_text_action.dart';
import 'harness_comments.dart';
import '../state/app_state.dart';
import '../ws/ws_conn.dart';

typedef ShareAction = Future<Map<String, dynamic>> Function(
  String action,
  Map<String, dynamic> payload,
);

Future<void> showShareHarnessDialog(
  BuildContext context,
  AppNotifier app,
  String machineId,
  String agentId,
  String name,
) => showTerminalPrompt<void>(
  context,
  builder: (_) => ShareHarnessDialog(
    name: name,
    manage: (action, payload) =>
        app.manageHarnessShares(machineId, agentId, action, payload),
  ),
);

class ShareHarnessDialog extends StatefulWidget {
  const ShareHarnessDialog({
    super.key,
    required this.name,
    required this.manage,
  });
  final String name;
  final ShareAction manage;
  @override
  State<ShareHarnessDialog> createState() => _ShareHarnessDialogState();
}

class _ShareHarnessDialogState extends State<ShareHarnessDialog> {
  final _emails = TextEditingController();
  List<Map<String, dynamic>> _shares = [];
  bool _loading = true, _busy = false;
  String? _error, _notice;
  int _days = 30;
  Map<String, dynamic>? _link;
  bool _collaboration = false, _comments = false, _manualCopy = false;
  Timer? _presence;
  int _revision = 0;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _presence = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) unawaited(_load(quiet: true));
    });
  }

  @override
  void dispose() {
    _presence?.cancel();
    _emails.dispose();
    super.dispose();
  }

  String _message(Object error) =>
      error is WsRequestFailure && error.code == 'UNSUPPORTED'
      ? 'Update Harness on this machine to start sharing.'
      : error is WsRequestFailure && error.detail != null
      ? error.detail!
      : 'Could not reach this harness. Check the connection and try again.';
  void _accept(Map<String, dynamic> response) {
    _collaboration = response['collaboration'] == true;
    _link = response['link'] is Map
        ? Map<String, dynamic>.from(response['link'] as Map)
        : null;
    _shares = [
      for (final row in response['shares'] as List? ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<void> _load({bool quiet = false}) async {
    if (_refreshing || _busy) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final response = await widget.manage('list', const {});
      if (mounted && revision == _revision) {
        setState(() {
          _accept(response);
          _loading = false;
          if (!quiet) _error = null;
        });
      }
    } catch (error) {
      if (mounted && !quiet && revision == _revision) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _invite() async {
    if (_busy) return;
    final emails = _emails.text
        .split(RegExp(r'[,;\s]+'))
        .where((e) => e.isNotEmpty)
        .map((e) => e.toLowerCase())
        .toSet()
        .toList();
    if (emails.isEmpty ||
        emails.length > 20 ||
        emails.any((e) => !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e))) {
      setState(() {
        _error = 'Enter up to 20 valid email addresses, separated by commas.';
        _notice = null;
      });
      return;
    }
    setState(() {
      _revision++;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await widget.manage('invite', {
        'emails': emails,
        'days': _days,
      });
      if (mounted) {
        setState(() {
          _accept(response);
          _emails.clear();
          _notice = _shares.any((s) => s['error'] != null)
              ? 'Some invitations could not be shared. Check the details below.'
              : _shares.any((s) => s['pending'] == true)
              ? 'Invitations saved. They will appear when the connection returns.'
              : '${emails.length == 1 ? '1 person now has' : '${emails.length} people now have'} view-only access.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id) async {
    if (_busy) return;
    setState(() {
      _revision++;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await widget.manage('remove', {'id': id});
      if (mounted) {
        setState(() {
          _accept(response);
          _notice = 'Access removed.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkAction(String visibility, {bool copy = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _revision++;
      _error = null;
      _notice = null;
    });
    try {
      if (!copy || _link == null || _link?['visibility'] == 'off') {
        _accept(await widget.manage('link', {'visibility': visibility}));
      }
      if (copy && _link?['pending'] != true && _link?['error'] == null) {
        final url = _link?['url'] as String?;
        if (url == null) throw StateError('Link unavailable');
        await Clipboard.setData(ClipboardData(text: url));
        _manualCopy = false;
        if (mounted) setState(() => _notice = 'Link copied.');
      } else if (mounted) {
        setState(
          () => _notice =
              _link?['error'] as String? ??
              (_link?['pending'] == true
                  ? 'Saved. Waiting for the connection before the link is ready.'
                  : visibility == 'off'
                  ? 'Sharing stopped.'
                  : 'Access updated.'),
        );
      }
    } catch (error) {
      _manualCopy = copy && _link?['url'] != null;
      if (mounted) {
        setState(
          () => _error = copy && _link?['url'] != null
              ? 'Could not copy. Select the link below and copy it.'
              : _message(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([terminalFontStore, terminalThemeStore]),
      builder: (context, _) {
        final cell = terminalCellSizeOf(context);
        final theme = terminalThemeFor(
          grid.AppTheme.palette.value,
          terminalThemeStore.value,
        );
        final style = terminalContentStyle(color: theme.foreground);
        final muted = style.copyWith(
          color: theme.foreground.withValues(alpha: .6),
        );
        final isPublic = _link?['visibility'] == 'public';
        final disabled = _busy || _loading;
        final gap = SizedBox(height: cell.height);
        Widget action(String label, VoidCallback? run) =>
            TerminalTextAction(label: label, onPressed: run);
        return TerminalPromptKeys(
          cancel: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: theme.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.symmetric(
              horizontal: cell.width * 2,
              vertical: cell.height * 2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kTerminalCornerRadius),
              side: terminalPaneBorder(focused: true),
            ),
            child: DefaultTextStyle(
              style: style,
              child: SizedBox(
                width: cell.width * 68,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .8,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: cell.width * 2,
                      vertical: cell.height,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Share ${widget.name}',
                                overflow: TextOverflow.ellipsis,
                                style: style.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_collaboration)
                              action(
                                _comments ? 'Access' : 'Comments',
                                () => setState(() => _comments = !_comments),
                              ),
                            action('Done', () => Navigator.of(context).pop()),
                          ],
                        ),
                        gap,
                        if (_comments)
                          Flexible(
                            child: SizedBox(
                              height: cell.height * 25,
                              child: HarnessComments(manage: widget.manage),
                            ),
                          )
                        else
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_loading) const Text('Loading sharing…'),
                                  if (!_loading && !_collaboration)
                                    const Text(
                                      'Update Harness on this machine to share browser links and comments.',
                                    ),
                                  if (_collaboration) ...[
                                    Wrap(
                                      children: [
                                        action(
                                          '${!isPublic ? 'x' : ' '} Private',
                                          disabled
                                              ? null
                                              : () => _linkAction('private'),
                                        ),
                                        action(
                                          '${isPublic ? 'x' : ' '} Public',
                                          disabled
                                              ? null
                                              : () => _linkAction('public'),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      isPublic
                                          ? 'Anyone with the link can view live output and comments.'
                                          : 'Only the emails you add can view and comment.',
                                      style: muted,
                                    ),
                                    gap,
                                    Wrap(
                                      children: [
                                        action(
                                          _busy ? 'Saving…' : 'Copy link',
                                          disabled
                                              ? null
                                              : () => _linkAction(
                                                  'private',
                                                  copy: true,
                                                ),
                                        ),
                                        if (_link != null &&
                                            _link?['visibility'] != 'off')
                                          action(
                                            'Stop sharing',
                                            disabled
                                                ? null
                                                : () => _linkAction('off'),
                                          ),
                                      ],
                                    ),
                                    if (_manualCopy && _link?['url'] is String)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: cell.height,
                                        ),
                                        child: SelectableText(
                                          _link!['url'] as String,
                                          style: muted,
                                        ),
                                      ),
                                    if (_link?['error'] != null)
                                      Text('${_link!['error']}'),
                                    gap,
                                  ],
                                  if (!isPublic) ...[
                                    const Text('Add people by email'),
                                    TextField(
                                      controller: _emails,
                                      autofocus: true,
                                      enabled: !disabled,
                                      keyboardType: TextInputType.emailAddress,
                                      maxLines: 2,
                                      minLines: 1,
                                      style: style,
                                      cursorColor: theme.cursor,
                                      decoration: InputDecoration(
                                        hintText: 'name@example.com, another@example.com',
                                        hintStyle: muted,
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: cell.height / 2,
                                        ),
                                      ),
                                      onSubmitted: (_) => _invite(),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        const Text('Expires in '),
                                        for (final days in [7, 30, 90])
                                          action(
                                            '${_days == days ? 'x ' : ''}$days days',
                                            disabled
                                                ? null
                                                : () => setState(
                                                    () => _days = days,
                                                  ),
                                          ),
                                        action(
                                          'Add people',
                                          disabled ||
                                                  _emails.text.trim().isEmpty
                                              ? null
                                              : _invite,
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_error != null)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: cell.height,
                                      ),
                                      child: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          _error!,
                                          style: style.copyWith(
                                            color: theme.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_notice != null)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: cell.height,
                                      ),
                                      child: Semantics(
                                        liveRegion: true,
                                        child: Text(_notice!),
                                      ),
                                    ),
                                  gap,
                                  if (!_loading && !isPublic && _shares.isEmpty)
                                    Text(
                                      'No invited people yet.',
                                      style: muted,
                                    ),
                                  for (final share
                                      in isPublic
                                          ? <Map<String, dynamic>>[]
                                          : _shares)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: cell.height,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${share['email']}',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              action(
                                                'Remove',
                                                _busy
                                                    ? null
                                                    : () => _remove(
                                                        share['id'] as String,
                                                      ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _recipientStatus(share),
                                            style: muted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    'Keep your machine online while people watch. Viewers can comment; they cannot control your agent.',
                                    style: muted,
                                  ),
                                  if (_error != null && !_busy)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: action('Retry', () => _load()),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _recipientStatus(Map<String, dynamic> share) {
    final expires = DateTime.tryParse(share['expiresAt'] as String? ?? '')
        ?.toLocal();
    return share['error'] as String? ??
        (share['pending'] == true
            ? 'Waiting for connection'
            : share['expired'] == true
            ? 'Expired · add again to renew'
            : (share['watching'] as num? ?? 0) > 0
            ? 'Watching now · Can view'
            : 'Can view${expires == null ? '' : ' · Until ${expires.month}/${expires.day}/${expires.year}'}');
  }
}
