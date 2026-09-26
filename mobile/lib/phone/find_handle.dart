import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/notify/agent_notice.dart';
import 'package:harness_mobile/notify/agent_unread.dart';
import 'package:harness_mobile/notify/unread_marks.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart';

/// The foot of Focus: the one way to another agent.
///
/// Focus holds a single agent and has no sideways swipe (see
/// `docs/plans/2026-09-26-001-mobile-zero-questions.md`); this bar is what brings Find up over it.
/// A swipe up on it opens Find, and so does a tap — so nobody has to know there is a gesture.
///
/// ⚠️ **The swipe starts HERE, never on the terminal.** The terminal scrolls vertically through its
/// scrollback, and the screen's bottom edge is iOS's own go-home swipe; a bar of its own, labelled,
/// above the home indicator is the one place an upward drag means nothing else.
class FindHandle extends StatefulWidget {
  const FindHandle({
    super.key,
    required this.onOpen,
    this.unread,
    this.bottomInset = 0,
  });

  final VoidCallback onOpen;

  /// Agents that finished or are asking since they were last looked at: a dot beside the label.
  final AgentUnread? unread;

  /// The home indicator or gesture handle under the bar — the page does not reserve it for the
  /// terminal, so the bar carries it.
  final double bottomInset;

  /// The bar's own height, above [bottomInset]: a full touch target.
  static const double height = 44;

  @override
  State<FindHandle> createState() => _FindHandleState();
}

class _FindHandleState extends State<FindHandle> {
  /// How far up a drag has to travel before it counts, in logical pixels.
  static const double _reach = 16;

  /// An upward flick shorter than [_reach] still counts at this speed.
  static const double _flick = 300;

  double _dragged = 0;
  bool _fired = false;

  void _open() {
    if (_fired) return;
    _fired = true;
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      label: 'Find an agent',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _fired = false;
          _open();
        },
        onVerticalDragStart: (_) {
          _dragged = 0;
          _fired = false;
        },
        onVerticalDragUpdate: (details) {
          _dragged -= details.primaryDelta ?? 0;
          if (_dragged >= _reach) _open();
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) <= -_flick) _open();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.windowBg,
            border: Border(top: BorderSide(color: AppGlass.hair)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.bottomInset),
            child: SizedBox(
              height: FindHandle.height,
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.textFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.search300,
                          size: 15,
                          color: AppPalette.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Find',
                          style: TextStyle(
                            color: AppPalette.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.unread case final unread?)
                          _UnreadDot(unread: unread),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Amber while an agent is asking, the done colour otherwise; nothing when nothing is unread.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.unread});

  final AgentUnread unread;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: unread,
    builder: (context, _) {
      if (unread.count == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: unreadColor(
              unread.anyQuestion ? NoticeKind.question : NoticeKind.done,
            ),
            shape: BoxShape.circle,
          ),
        ),
      );
    },
  );
}
