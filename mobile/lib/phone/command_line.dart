import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tty.dart';

/// Focus's command line — vim's last line, there only while it has something to say. Nothing is
/// drawn at the foot of Focus otherwise: the terminal is the screen.
///
/// Two modes, highest first:
/// - **message** — two seconds of `display-message`: black on yellow, or white on red for an error
///   (`✗ no match — tap an answer` has to be read over the keys it is about);
/// - **prompt** — an agent's question is open: tmux yellow, its answers as keys,
///   ` 1 yes │ 2 always │ 3 no `, like tmux's `confirm-before`.
///
/// Drawn 2 rows tall on the terminal's grid; each key's touch reaches [slop] further down into the
/// home-indicator strip, so every target is at least 44pt tall.
class CommandLine extends StatelessWidget {
  const CommandLine({
    super.key,
    this.slop = 0,
    this.prompt,
    this.promptNote,
    this.message,
  });

  /// Whether there is anything to draw.
  bool get shows => prompt != null || promptNote != null || message != null;

  /// Prompt mode — an agent's question is open: the bar goes tmux yellow and becomes its answer
  /// keys, ` 1 yes │ 2 always │ 3 no `, like tmux's `confirm-before`.
  final List<({String label, VoidCallback onTap})>? prompt;

  /// Prompt mode with no keys to offer (a dialog only partly on screen): one line saying so.
  final String? promptNote;

  /// tmux's message line, for two seconds: black on yellow, or white on red for an error.
  final ({String text, bool error})? message;

  /// How far each word's touch reaches below the drawn bar.
  final double slop;

  /// The drawn height: two terminal rows.
  static double heightOf(Tty tty) => 2 * tty.row;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final ink = tty.theme.black;
    final bar = heightOf(tty);
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
    return const SizedBox.shrink();
  }
}
