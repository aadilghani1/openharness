import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tty.dart';
import 'tty_controls.dart';

/// Focus's title: whose terminal this is, as a pane title would say it — the agent, then where it
/// works.
///
/// ```
///  hn                                  1 asking  …
///  M2:autonomous-harness  main
/// ```
///
/// ⚠️ **A title, not a tab bar.** Agents are like vim's buffers: one on screen, the rest a search
/// away (the name opens Find, as `:b` would). Nothing here lists other agents; the one exception
/// is `1 asking` — harnesses elsewhere asking you something — since nothing else on the screen
/// would say so.
///
/// It floats over the terminal's top rows and the page slides it away while you read back through
/// the history; back at the end of the output, it returns (see `TerminalChromeScroll`).
class TerminalTitle extends StatelessWidget {
  const TerminalTitle({
    super.key,
    required this.name,
    required this.onFind,
    this.place,
    this.branch,
    this.asking,
    this.onHoldName,
    this.state,
    this.action,
    this.onActions,
  });

  final String name;

  /// `machine:folder` — where the agent works.
  final String? place;

  final String? branch;

  /// Harnesses elsewhere asking — `api-fix asking`, or `2 asking` — in yellow; a tap opens Find.
  final String? asking;

  /// Holding the name: back to the last harness (tmux's `prefix L`, vim's `:b#`).
  final VoidCallback? onHoldName;

  /// A word for a connection state that is not plain live — `attaching`, `reconnecting` — or null.
  final String? state;

  /// A way out of a stuck state — `take control`, `reconnect` — as a word to tap.
  final ({String label, VoidCallback onTap})? action;

  final VoidCallback onFind;
  final VoidCallback? onActions;

  /// A long branch shortened in the middle — `fix/login-refresh-token` → `fix/logi…sh-token` — where
  /// both ends say which one it is; cut at the end, `fix/logi` said nothing.
  static String _short(String branch) => branch.length <= 18
      ? branch
      : '${branch.substring(0, 8)}…${branch.substring(branch.length - 8)}';

  /// Three terminal rows: two of text and half a row of air above and below, which is also what
  /// makes each word a 44pt target.
  static double heightOf(Tty tty) => 3 * tty.row;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final height = heightOf(tty);
    Widget word(
      String text, {
      VoidCallback? onTap,
      String? semanticsLabel,
      Color? color,
      Color? background,
      FontWeight weight = FontWeight.w400,
      double? size,
    }) {
      final drawn = Padding(
        padding: EdgeInsets.symmetric(horizontal: tty.cell / 2),
        child: TtyText(
          text,
          color: color ?? tty.text,
          background: background,
          weight: weight,
          size: size,
        ),
      );
      if (onTap == null) return Center(child: drawn);
      return Semantics(
        button: true,
        label: semanticsLabel ?? text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 6 * tty.cell),
            child: SizedBox(
              height: height,
              child: Center(child: drawn),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tty.ground,
        border: Border(bottom: BorderSide(color: tty.dim, width: 0.5)),
      ),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              // The name and where it runs take what the words at the right leave — all of it when
              // there are none.
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Find an agent',
                  child: GestureDetector(
                    key: const ValueKey('terminal-find'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onFind();
                    },
                    onLongPress: onHoldName == null
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            onHoldName!();
                          },
                    child: Padding(
                      padding: const EdgeInsets.only(left: Tty.origin),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TtyText(
                            name,
                            weight: FontWeight.w700,
                            size: TtySize.title,
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                if (place case final place?)
                                  TextSpan(
                                    text: place,
                                    style: tty.style(
                                      color: tty.faint,
                                      size: TtySize.meta,
                                    ),
                                  ),
                                if (branch case final branch?
                                    when branch.trim().isNotEmpty)
                                  TextSpan(
                                    text:
                                        '${place == null ? '' : ' · '}${_short(branch)}',
                                    style: tty.style(
                                      color: tty.magenta,
                                      size: TtySize.meta,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The words between the name and `…` take only what they need, and never more than
              // under half the row: clipped rather than crowding out where the harness runs.
              if (asking != null || state != null || action != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                  child: ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (asking case final asking?)
                            word(
                              asking,
                              color: tty.yellow,
                              size: TtySize.meta,
                              onTap: onFind,
                              semanticsLabel: '$asking — open Find',
                            ),
                          if (state case final state?)
                            word(state, color: tty.faint),
                          if (action case final action?)
                            word(
                              '[${action.label}]',
                              weight: FontWeight.w700,
                              onTap: action.onTap,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (onActions != null)
                word(
                  // SF Mono's own glyph — it has no ⋮, and a fallback face would break the grid.
                  '…',
                  weight: FontWeight.w700,
                  onTap: onActions,
                  semanticsLabel: 'Harness actions',
                ),
              SizedBox(width: Tty.origin - tty.cell / 2),
            ],
          ),
        ),
      ),
    );
  }
}
