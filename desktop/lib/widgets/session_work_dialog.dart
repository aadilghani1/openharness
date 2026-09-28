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
  bool _loading = false, _showCompleted = false;
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
        _error = 'History unavailable · showing saved data';
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
        final branches = [...?data?.branchRows];
        branches.sort((a, b) {
          final recent =
              (data?.isRecentBranch(b) == true ? 1 : 0) -
              (data?.isRecentBranch(a) == true ? 1 : 0);
          if (recent != 0) return recent;
          bool open(AgentBranchRow row) => row.pullRequests.any(
            (pr) => pr.state == 'Open' || pr.state == 'Draft',
          );
          final review = (open(b) ? 1 : 0) - (open(a) ? 1 : 0);
          if (review != 0) return review;
          final checked = (b.checkedOut ? 1 : 0) - (a.checkedOut ? 1 : 0);
          return checked != 0 ? checked : a.branch.compareTo(b.branch);
        });
        final repositories = branches.map((row) => row.repository).toSet();
        final commonRepository = repositories.length == 1
            ? repositories.single
            : null;
        String repositoryName(String repository) =>
            repository.replaceFirst(RegExp(r'^github\.com/'), '');
        final prs = [...?data?.pullRequests];
        int rank(AgentWorkPr pr) => switch (pr.state) {
          'Open' || 'Draft' => 0,
          'Merged' || 'Closed' => 2,
          _ => 1,
        };
        int comparePrs(AgentWorkPr a, AgentWorkPr b) {
          final order = rank(a).compareTo(rank(b));
          if (order != 0) return order;
          final recency = b.at.compareTo(a.at);
          return recency != 0
              ? recency
              : a.url.toString().compareTo(b.url.toString());
        }

        prs.sort(comparePrs);
        bool completed(AgentWorkPr pr) =>
            pr.state == 'Merged' || pr.state == 'Closed';
        final recentUrls = branches
            .where((b) => data?.isRecentBranch(b) == true)
            .expand((b) => b.pullRequests.map((pr) => pr.url))
            .toSet();
        final completedCount = prs
            .where((pr) => completed(pr) && !recentUrls.contains(pr.url))
            .length;
        bool completedBranch(AgentBranchRow branch) =>
            data?.isRecentBranch(branch) != true &&
            branch.pullRequests.isNotEmpty &&
            branch.pullRequests.every(completed);
        final ongoingPrs =
            prs
                .where((pr) => !completed(pr) || recentUrls.contains(pr.url))
                .toList()
              ..sort((a, b) {
                final recent =
                    (recentUrls.contains(b.url) ? 1 : 0) -
                    (recentUrls.contains(a.url) ? 1 : 0);
                return recent != 0 ? recent : comparePrs(a, b);
              });
        final completedPrs = prs
            .where((pr) => completed(pr) && !recentUrls.contains(pr.url))
            .toList();
        final visibleUrls = {
          ...ongoingPrs.take(_visiblePrs).map((pr) => pr.url),
          if (_showCompleted)
            ...completedPrs.take(_visiblePrs).map((pr) => pr.url),
        };
        final groupedUrls = branches
            .expand((branch) => branch.pullRequests.map((pr) => pr.url))
            .toSet();
        final ungrouped = prs.where(
          (pr) => visibleUrls.contains(pr.url) && !groupedUrls.contains(pr.url),
        );
        Widget text(String value, {bool dim = false}) => Text(
          value,
          style: dim ? muted : style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        Widget line(String value, {bool dim = false}) => SizedBox(
          height: cell.height,
          child: Tooltip(
            message: value,
            child: text(value, dim: dim),
          ),
        );
        final summary = [
          if (commonRepository != null) repositoryName(commonRepository),
          '${branches.length} ${branches.length == 1 ? 'branch' : 'branches'}',
          '${prs.length} ${prs.length == 1 ? 'PR' : 'PRs'}',
        ].join(' · ');
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
          child: ConstrainedBox(
            key: const ValueKey('work-dialog-surface'),
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                math.min(
                  MediaQuery.sizeOf(context).height - cell.height * 4,
                  cell.height * 28,
                ),
              ),
            ),
            child: SizedBox(
              width: cell.width * 80,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: cell.width * 2,
                  vertical: cell.height,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < cell.width * 52;
                    final rows = <Widget>[];
                    void separate() {
                      if (rows.isNotEmpty) {
                        rows.add(SizedBox(height: cell.height));
                      }
                    }

                    void addPr(AgentWorkPr pr) {
                      final number = '#${pr.url.pathSegments.last}';
                      final state = pr.state ?? 'Unknown';
                      final title =
                          pr.title ?? pr.url.pathSegments.take(2).join('/');
                      final details = [
                        '$number · $title · $state',
                        pr.url.pathSegments.take(2).join('/'),
                        if (pr.headBranch != null)
                          '${pr.headBranch}${pr.baseBranch == null ? '' : ' → ${pr.baseBranch}'}',
                        if (pr.checkedAt != null)
                          'Checked ${localWorkTime(pr.checkedAt!)}',
                        'Open on GitHub',
                      ].join('\n');
                      rows.add(
                        Padding(
                          key: ValueKey('work-pr-row-${pr.url}'),
                          padding: EdgeInsets.only(left: cell.width * 2),
                          child: SizedBox(
                            height: cell.height,
                            child: Tooltip(
                              message: details,
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
                                child: Semantics(
                                  label: details.replaceAll('\n', ' · '),
                                  excludeSemantics: true,
                                  child: Row(
                                    children: [
                                      if (compact)
                                        Expanded(child: text(number))
                                      else ...[
                                        SizedBox(
                                          width: cell.width * 7,
                                          child: text(number, dim: true),
                                        ),
                                        Expanded(child: text(title)),
                                      ],
                                      SizedBox(width: cell.width * 2),
                                      text(state, dim: true),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      if (compact) {
                        rows.add(
                          Padding(
                            padding: EdgeInsets.only(left: cell.width * 2),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => unawaited(_open(pr.url)),
                                child: ExcludeSemantics(
                                  child: line(title, dim: true),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (_unavailable.contains(pr.url.toString())) {
                        rows.add(
                          Padding(
                            padding: EdgeInsets.only(left: cell.width * 2),
                            child: line(
                              'GitHub unavailable · saved status',
                              dim: true,
                            ),
                          ),
                        );
                      }
                    }

                    void addBranch(AgentBranchRow branch) {
                      final visiblePrs =
                          branch.pullRequests
                              .where((pr) => visibleUrls.contains(pr.url))
                              .toList()
                            ..sort(comparePrs);
                      // Keep checked-out and PR-less branches visible. Completed groups
                      // outside this page appear with their PRs when Show more is chosen.
                      if (!branch.checkedOut &&
                          branch.pullRequests.isNotEmpty &&
                          visiblePrs.isEmpty) {
                        return;
                      }
                      separate();
                      if (commonRepository == null &&
                          branch.repository != null) {
                        rows.add(
                          line(repositoryName(branch.repository!), dim: true),
                        );
                      }
                      rows.add(
                        SizedBox(
                          height: cell.height,
                          child: Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: branch.branch,
                                  child: text(branch.branch),
                                ),
                              ),
                              if (branch.checkedOut && !compact) ...[
                                SizedBox(width: cell.width * 2),
                                Tooltip(
                                  message: data?.isRecentBranch(branch) == true
                                      ? data!.explanation
                                      : 'Branch currently checked out in a location associated with this session.',
                                  child: text(
                                    data?.isRecentBranch(branch) == true
                                        ? 'Recent work'
                                        : 'Checked out',
                                    dim: true,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                      if (branch.checkedOut && compact) {
                        rows.add(
                          line(
                            data?.isRecentBranch(branch) == true
                                ? 'Recent work'
                                : 'Checked out',
                            dim: true,
                          ),
                        );
                      }
                      for (final pr in visiblePrs) {
                        addPr(pr);
                      }
                    }

                    for (final branch in branches.where(
                      (b) => !completedBranch(b),
                    )) {
                      addBranch(branch);
                    }
                    final otherOpenPrs = ungrouped.where(
                      (pr) => !completed(pr),
                    );
                    if (otherOpenPrs.isNotEmpty) {
                      separate();
                      rows.add(line('Pull requests', dim: true));
                      for (final pr in otherOpenPrs) {
                        addPr(pr);
                      }
                    }
                    if (completedCount > 0) {
                      separate();
                      rows.add(
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TerminalTextAction(
                            key: const ValueKey('work-completed'),
                            label: _showCompleted
                                ? 'Hide completed'
                                : 'Completed ($completedCount)',
                            padding: EdgeInsets.zero,
                            onPressed: () => setState(
                              () => _showCompleted = !_showCompleted,
                            ),
                          ),
                        ),
                      );
                      if (_showCompleted) {
                        for (final branch in branches.where(completedBranch)) {
                          addBranch(branch);
                        }
                        final completedPrs = ungrouped.where(completed);
                        if (completedPrs.isNotEmpty) {
                          separate();
                          for (final pr in completedPrs) {
                            addPr(pr);
                          }
                        }
                      }
                    }
                    if (rows.isEmpty) {
                      rows.add(
                        line(
                          _loading
                              ? 'Reading session history…'
                              : 'No branches or pull requests recorded.',
                          dim: true,
                        ),
                      );
                    }
                    if (_nextOffset != null ||
                        ongoingPrs.length > _visiblePrs ||
                        _showCompleted && completedPrs.length > _visiblePrs) {
                      separate();
                      rows.add(
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TerminalTextAction(
                            label: 'Show more',
                            padding: EdgeInsets.zero,
                            onPressed: _loading
                                ? null
                                : () {
                                    final offset = _nextOffset ?? _visiblePrs;
                                    setState(() => _visiblePrs += 4);
                                    if (widget.online) {
                                      unawaited(_refresh(offset));
                                    }
                                  },
                          ),
                        ),
                      );
                    }
                    return Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
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
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          line('${widget.agent.displayName} · Branches & PRs'),
                          if (compact && commonRepository != null) ...[
                            line(repositoryName(commonRepository), dim: true),
                            line(
                              '${branches.length} branches · ${prs.length} PRs',
                              dim: true,
                            ),
                          ] else
                            line(summary, dim: true),
                          if (!widget.online)
                            line('Offline · saved data', dim: true)
                          else if (data?.state == 'unavailable' ||
                              data?.state == 'uncertain')
                            line('Git unavailable · saved history', dim: true),
                          SizedBox(height: cell.height),
                          Flexible(
                            child: ListView.builder(
                              key: const ValueKey('work-branch-list'),
                              shrinkWrap: true,
                              itemExtent: cell.height,
                              itemCount: rows.length,
                              itemBuilder: (_, index) => rows[index],
                            ),
                          ),
                          if (data?.truncated == true)
                            line('Some earlier history is omitted.', dim: true),
                          if (_error != null) line(_error!),
                          SizedBox(height: cell.height),
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                if (widget.online)
                                  TerminalTextAction(
                                    label: _loading ? 'Refreshing…' : 'Refresh',
                                    padding: EdgeInsets.zero,
                                    onPressed: _loading
                                        ? null
                                        : () => unawaited(_refresh(0)),
                                  ),
                                TerminalTextAction(
                                  label: 'Close',
                                  padding: EdgeInsets.zero,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
