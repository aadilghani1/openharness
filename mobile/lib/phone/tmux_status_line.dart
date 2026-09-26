import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tty.dart';

/// One agent's state, as tmux flags a window.
enum TmuxFlag {
  none,

  /// `#` — output since you looked (tmux's activity flag): the agent is working.
  working,

  /// `!` — the bell: the agent is asking you something. The whole word goes black on yellow.
  asking,

  /// `~` — tmux's silence flag: it finished, and you have not looked since.
  done,
}

/// One window on the status line: an agent, its marks and its flag.
class TmuxWindow {
  const TmuxWindow({
    required this.label,
    required this.onTap,
    this.machine,
    this.current = false,
    this.last = false,
    this.flag = TmuxFlag.none,
  });

  final String label;
  final VoidCallback onTap;

  /// The machine, drawn `@mini`, only when it is not the one the bar is on.
  final String? machine;

  /// The agent on screen — tmux's `*`.
  final bool current;

  /// The agent before it — tmux's `-`.
  final bool last;

  final TmuxFlag flag;

  String get text =>
      '$label${machine == null ? '' : '@$machine'}'
      '${current
          ? '*'
          : last
          ? '-'
          : ''}'
      '${switch (flag) {
        TmuxFlag.none => '',
        TmuxFlag.working => '#',
        TmuxFlag.asking => '!',
        TmuxFlag.done => '~',
      }}';
}

/// Focus's status line, as tmux draws it at the foot of the screen: `[M2] hn*# api-fix@mini! docs~`
/// on tmux's green, black ink, two terminal rows tall.
///
/// ⚠️ **tmux's own grammar, touch-sized.** The session in brackets is the machine and opens Find
/// (tmux's `C-b w`); each window is an agent, tapped to switch to it; `*` is the one on screen, `-`
/// the one before; one flag each — `!` asking (the whole word black on yellow, tmux's bell), `#`
/// working, `~` done and unread. No window numbers: they renumber on every switch and a phone has
/// no `C-b 2`. On the right: `+N!` for asking agents that did not fit, `esc` while the agent works
/// (it interrupts, no confirm), `…` for the agent's actions.
///
/// Drawn 2 rows tall on the terminal's grid; each word's touch reaches [slop] further down into the
/// home-indicator strip, so every target is at least 44pt tall.
class TmuxStatusLine extends StatelessWidget {
  const TmuxStatusLine({
    super.key,
    required this.session,
    required this.windows,
    required this.onFind,
    this.askingOverflow = 0,
    this.onEsc,
    this.state,
    this.action,
    this.onActions,
    this.slop = 0,
    this.prompt,
    this.promptNote,
    this.message,
  });

  /// Prompt mode — an agent's question is open: the bar goes tmux yellow and becomes its answer
  /// keys, ` 1 yes │ 2 always │ 3 no `, like tmux's `confirm-before`.
  final List<({String label, VoidCallback onTap})>? prompt;

  /// Prompt mode with no keys to offer (a dialog only partly on screen): one line saying so.
  final String? promptNote;

  /// tmux's message line, for two seconds: black on yellow, or white on red for an error.
  final ({String text, bool error})? message;

  /// The machine, drawn `[M2]`.
  final String session;
  final List<TmuxWindow> windows;
  final VoidCallback onFind;

  /// Asking agents that did not fit — drawn `+2!`, a tap opens Find.
  final int askingOverflow;

  /// `esc` — interrupt the agent on screen. Null while it is not working.
  final VoidCallback? onEsc;

  /// A word for a connection state that is not plain live — `attaching`, `reconnecting` — or null.
  final String? state;

  /// A way out of a stuck state — `take control`, `reconnect` — as a word to tap.
  final ({String label, VoidCallback onTap})? action;

  final VoidCallback? onActions;

  /// How far each word's touch reaches below the drawn bar.
  final double slop;

  /// The drawn height: two terminal rows.
  static double heightOf(Tty tty) => 2 * tty.row;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final ink = tty.theme.black;
    final bar = heightOf(tty);
    Widget word(
      String text, {
      VoidCallback? onTap,
      String? semanticsLabel,
      bool asking = false,
      FontWeight weight = FontWeight.w400,
    }) {
      final drawn = SizedBox(
        height: bar,
        child: Center(
          child: ColoredBox(
            color: asking ? tty.yellow : Colors.transparent,
            child: TtyText(text, color: ink, weight: weight),
          ),
        ),
      );
      final padded = Padding(
        padding: EdgeInsets.symmetric(horizontal: tty.cell / 2),
        child: drawn,
      );
      if (onTap == null) return padded;
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
            // At least six cells wide, and down into the home-indicator strip.
            constraints: BoxConstraints(minWidth: 6 * tty.cell),
            child: SizedBox(
              height: bar + slop,
              child: Align(alignment: Alignment.topCenter, child: padded),
            ),
          ),
        ),
      );
    }

    if (message case final message?) {
      return SizedBox(
        height: bar + slop,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            height: bar,
            width: double.infinity,
            color: message.error ? tty.red : tty.yellow,
            padding: const EdgeInsets.only(left: Tty.origin, right: Tty.origin),
            alignment: Alignment.centerLeft,
            child: TtyText(
              message.text,
              color: message.error ? tty.theme.brightWhite : ink,
            ),
          ),
        ),
      );
    }
    if (prompt != null || promptNote != null) {
      final keys = prompt ?? const [];
      return SizedBox(
        height: bar + slop,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: bar,
              child: ColoredBox(color: tty.yellow),
            ),
            if (keys.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: Tty.origin),
                child: SizedBox(
                  height: bar,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TtyText(promptNote ?? '', color: ink),
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < keys.length; i++) ...[
                    // The rule between keys: one row tall on the bar's centre line, drawn
                    // rather than typed — a `│` glyph sits on the text baseline, not the bar's.
                    if (i > 0)
                      SizedBox(
                        height: bar,
                        child: Center(
                          child: SizedBox(
                            width: 1,
                            height: tty.row,
                            child: ColoredBox(color: ink),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Answer ${keys[i].label}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            keys[i].onTap();
                          },
                          child: SizedBox(
                            height: bar + slop,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                height: bar,
                                child: Center(
                                  child: TtyText(
                                    keys[i].label,
                                    color: ink,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: bar + slop,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: bar,
            child: ColoredBox(color: tty.green),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: Tty.origin - tty.cell / 2),
              KeyedSubtree(
                key: const ValueKey('terminal-find'),
                child: word(
                  '[$session]',
                  onTap: onFind,
                  semanticsLabel: 'Find an agent',
                ),
              ),
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final window in windows)
                          word(
                            window.text,
                            asking: window.flag == TmuxFlag.asking,
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
              if (askingOverflow > 0)
                word(
                  '+$askingOverflow!',
                  asking: true,
                  onTap: onFind,
                  semanticsLabel: '$askingOverflow more asking',
                ),
              if (state case final state?) word(state),
              if (action case final action?)
                word(
                  '[${action.label}]',
                  weight: FontWeight.w700,
                  onTap: action.onTap,
                ),
              if (onEsc != null)
                word(
                  'esc',
                  onTap: onEsc,
                  semanticsLabel: 'Interrupt the agent',
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
        ],
      ),
    );
  }
}
