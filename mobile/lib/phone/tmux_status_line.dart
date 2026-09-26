import 'package:flutter/material.dart';

import 'tty.dart';

/// One window on the status line: an agent, and whether it is the one on screen.
class TmuxWindow {
  const TmuxWindow({
    required this.label,
    required this.onTap,
    this.current = false,
    this.last = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The agent on screen — tmux's `*`.
  final bool current;

  /// The agent before it — tmux's `-`.
  final bool last;
}

/// Focus's header, drawn as tmux draws its status line: `[M2] 0:hn* 1:api-fix- 2:docs` on tmux's
/// own green, black text, one line.
///
/// ⚠️ **tmux, not a phone header.** The session name in brackets is the machine; the windows are
/// the agents you were last in, current one starred — a tap on one switches to it, as `C-b 1` would.
/// The brackets open Find, tmux's `C-b w` tree of everything. On the right, only what is worth a
/// word: a state that is not "live", a way out of read-only, and ⋮ for the agent's actions.
class TmuxStatusLine extends StatelessWidget {
  const TmuxStatusLine({
    super.key,
    required this.session,
    required this.windows,
    required this.onFind,
    this.state,
    this.action,
    this.onActions,
  });

  /// The machine, drawn `[M2]`.
  final String session;
  final List<TmuxWindow> windows;
  final VoidCallback onFind;

  /// A word for a state that is not plain live — `attaching`, `reconnecting` — or null.
  final String? state;

  /// A way out of a stuck state — `take control`, `reconnect` — as a word to tap.
  final ({String label, VoidCallback onTap})? action;

  final VoidCallback? onActions;

  /// The line's height: one row of text and a little air, tmux's single line on a phone.
  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final ink = tty.theme.black;
    return ColoredBox(
      color: tty.green,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            _Word(
              key: const ValueKey('terminal-find'),
              text: '[$session]',
              color: ink,
              onTap: onFind,
              semanticsLabel: 'Find an agent',
              leading: 8,
            ),
            Expanded(
              child: ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final (index, window) in windows.indexed)
                        _Word(
                          text:
                              '$index:${window.label}${window.current
                                  ? '*'
                                  : window.last
                                  ? '-'
                                  : ''}',
                          color: ink,
                          weight: window.current
                              ? FontWeight.w700
                              : FontWeight.w400,
                          onTap: window.current ? onFind : window.onTap,
                          semanticsLabel: window.current
                              ? 'Find an agent'
                              : 'Switch to ${window.label}',
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (state case final state?)
              _Word(text: state, color: ink),
            if (action case final action?)
              _Word(
                text: '[${action.label}]',
                color: ink,
                weight: FontWeight.w700,
                onTap: action.onTap,
              ),
            if (onActions != null)
              _Word(
                // SF Mono's own glyph — it has no ⋮, and a fallback face would break the grid.
                text: '…',
                color: ink,
                weight: FontWeight.w700,
                onTap: onActions,
                semanticsLabel: 'Harness actions',
                trailing: 12,
                leading: 12,
              ),
          ],
        ),
      ),
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({
    super.key,
    required this.text,
    required this.color,
    this.weight = FontWeight.w400,
    this.onTap,
    this.semanticsLabel,
    this.leading = 6,
    this.trailing = 6,
  });

  final String text;
  final Color color;
  final FontWeight weight;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final double leading;
  final double trailing;

  @override
  Widget build(BuildContext context) {
    final word = Padding(
      padding: EdgeInsets.fromLTRB(leading, 0, trailing, 0),
      child: TtyText(text, color: color, weight: weight),
    );
    if (onTap == null) return word;
    return TtyTap(
      onTap: onTap,
      semanticsLabel: semanticsLabel,
      minHeight: TmuxStatusLine.height,
      child: word,
    );
  }
}
