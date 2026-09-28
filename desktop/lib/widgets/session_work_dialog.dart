import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/agent_git_context.dart';
import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';
import 'box_chrome.dart';
import 'terminal_text_action.dart';

/// Inspection only. This surface never sends terminal input or mutates a checkout.
class SessionWorkDialog extends StatefulWidget {
  const SessionWorkDialog({
    super.key,
    required this.agent,
    required this.read,
    this.online = true,
    this.open,
  });
  final Agent agent;
  final Future<Map<String, dynamic>> Function(int offset) read;
  final bool online;
  final Future<bool> Function(Uri)? open;
  @override
  State<SessionWorkDialog> createState() => _SessionWorkDialogState();
}

class _SessionWorkDialogState extends State<SessionWorkDialog> {
  AgentGitContext? _data;
  bool _loading = false;
  String? _error;
  int? _nextOffset;
  int _revision = 0, _visiblePrs = 4;
  final _unavailable = <String>{};
  @override
  void initState() {
    super.initState();
    _data = widget.agent.gitContext;
    if (widget.online) unawaited(_refresh(0));
  }

  Future<void> _refresh(int offset) async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic> result;
    try {
      result = await widget.read(offset);
    } catch (_) {
      result = {'status': 'unavailable'};
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _loading = false;
      final raw = result['gitContext'];
      if (raw is Map && result['history'] is Map) {
        _nextOffset = result['nextOffset'] is int
            ? result['nextOffset'] as int
            : null;
        _data =
            AgentGitContext.fromJson({...raw, 'history': result['history']}) ??
            _data;
        for (final lookup
            in result['lookups'] is List
                ? result['lookups'] as List
                : const []) {
          if (lookup is! Map || lookup['url'] is! String) continue;
          if (lookup['status'] == 'unavailable') {
            _unavailable.add(lookup['url']);
          } else {
            _unavailable.remove(lookup['url']);
          }
        }
      } else {
        _error = 'Work history is unavailable. Showing saved observations.';
      }
    });
  }

  Future<void> _open(Uri uri) async {
    bool opened;
    try {
      opened =
          await (widget.open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      opened = false;
    }
    if (mounted && !opened) setState(() => _error = 'Could not open GitHub.');
  }

  @override
  void dispose() {
    _revision++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TerminalFontScope.watch(context);
    grid.AppTheme.watch(context);
    return ValueListenableBuilder(
      valueListenable: terminalThemeStore,
      builder: (context, _, _) {
        final theme = terminalThemeFor(
          grid.AppTheme.palette.value,
          terminalThemeStore.value,
        );
        final cell = terminalCellSizeOf(context);
        final style = terminalContentStyle(color: theme.foreground);
        final muted = style.copyWith(
          color: theme.foreground.withValues(alpha: .65),
        );
        final data = _data;
        final branchRows = data?.branchRows ?? <AgentBranchRow>[];
        final showRepositories =
            branchRows.map((row) => row.repository).toSet().length > 1;
        final prs = [...?data?.pullRequests];
        int rank(AgentWorkPr pr) => switch (pr.state) {
          'Open' || 'Draft' => 0,
          'Merged' || 'Closed' => 2,
          _ => 1,
        };
        prs.sort((a, b) {
          final order = rank(a).compareTo(rank(b));
          if (order != 0) return order;
          final recency = b.at.compareTo(a.at);
          return recency != 0
              ? recency
              : a.url.toString().compareTo(b.url.toString());
        });
        Widget line(String text, {bool dim = false}) => SizedBox(
          height: cell.height,
          child: Tooltip(
            message: text,
            child: Text(
              text,
              style: dim ? muted : style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        return Dialog(
          backgroundColor: theme.background,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(
            horizontal: cell.width * 2,
            vertical: cell.height * 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kTerminalCornerRadius),
            side: terminalPaneBorder(focused: true),
          ),
          child: SizedBox(
            width: cell.width * 84,
            height: math.max(
              0,
              math.min(
                MediaQuery.sizeOf(context).height - cell.height * 4,
                cell.height * 30,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: cell.width * 2,
                vertical: cell.height,
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    FocusScope.of(context).nextFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    FocusScope.of(context).previousFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(
                      '${widget.agent.displayName} · Branches and pull requests',
                    ),
                    line(
                      widget.online
                          ? data?.explanation ??
                                'Branches and pull requests for this session.'
                          : 'Offline · saved branches and pull requests',
                      dim: true,
                    ),
                    SizedBox(height: cell.height),
                    Expanded(
                      child: ListView(
                        children: [
                          line('Branches (${branchRows.length})'),
                          if (branchRows.isEmpty)
                            line(
                              data?.branchLabel ?? 'No branches recorded yet.',
                              dim: true,
                            ),
                          for (final branch in branchRows) ...[
                            line(
                              '${branch.branch}${branch.checkedOut ? ' · Checked out' : ''}',
                            ),
                            if (showRepositories && branch.repository != null)
                              line(branch.repository!, dim: true),
                            if (branch.pullRequests.isNotEmpty)
                              line(
                                branch.pullRequests
                                    .map(
                                      (pr) =>
                                          '#${pr.url.pathSegments.last} ${pr.state ?? 'State unknown'}',
                                    )
                                    .join(' · '),
                                dim: true,
                              ),
                          ],
                          SizedBox(height: cell.height),
                          line('Pull requests (${prs.length})'),
                          if (prs.isEmpty)
                            line(
                              'No pull requests observed for this session.',
                              dim: true,
                            ),
                          for (final pr in prs.take(_visiblePrs)) ...[
                            SizedBox(
                              key: ValueKey('work-pr-row-${pr.url}'),
                              height: cell.height,
                              child: TextButton(
                                key: ValueKey('work-pr-${pr.url}'),
                                onPressed: () => unawaited(_open(pr.url)),
                                style:
                                    TextButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      foregroundColor: theme.foreground,
                                      textStyle: style,
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: const RoundedRectangleBorder(),
                                      splashFactory: NoSplash.splashFactory,
                                    ).copyWith(
                                      overlayColor:
                                          WidgetStateProperty.resolveWith(
                                            (states) =>
                                                states.any(
                                                  {
                                                    WidgetState.focused,
                                                    WidgetState.hovered,
                                                    WidgetState.pressed,
                                                  }.contains,
                                                )
                                                ? theme.selection
                                                : Colors.transparent,
                                          ),
                                    ),
                                child: Tooltip(
                                  message: '${pr.title ?? ''} · ${pr.url}',
                                  child: Text(
                                    '#${pr.url.pathSegments.last}  ${pr.state ?? 'State unknown'}  ${pr.title ?? pr.url.pathSegments.take(2).join('/')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    semanticsLabel:
                                        '${pr.title ?? ''} · ${pr.url} · ${pr.state ?? 'State unknown'} · Open on GitHub',
                                  ),
                                ),
                              ),
                            ),
                            if (pr.headBranch case final branch?)
                              line(
                                '${pr.url.pathSegments.take(2).join('/')} · $branch${pr.baseBranch == null ? '' : ' → ${pr.baseBranch}'}',
                                dim: true,
                              ),
                            if (_unavailable.contains(pr.url.toString()))
                              line(
                                'GitHub unavailable · showing last known state',
                                dim: true,
                              )
                            else if (pr.checkedAt case final at?)
                              line('Checked ${localWorkTime(at)}', dim: true),
                          ],
                          if (_nextOffset != null || prs.length > _visiblePrs)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TerminalTextAction(
                                label: 'Show more',
                                onPressed: _loading
                                    ? null
                                    : () {
                                        final offset =
                                            _nextOffset ?? _visiblePrs;
                                        setState(() => _visiblePrs += 4);
                                        if (widget.online) {
                                          unawaited(_refresh(offset));
                                        }
                                      },
                              ),
                            ),
                          SizedBox(height: cell.height),
                          line(
                            data?.truncated == true
                                ? 'Older observations are omitted.'
                                : 'History includes recorded branches and PRs; earlier activity may be missing.',
                            dim: true,
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) line(_error!),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          if (widget.online)
                            TerminalTextAction(
                              label: _loading ? 'Refreshing…' : 'Refresh',
                              onPressed: _loading
                                  ? null
                                  : () => unawaited(_refresh(0)),
                            ),
                          TerminalTextAction(
                            label: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
