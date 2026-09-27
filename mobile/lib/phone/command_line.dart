import 'package:flutter/material.dart';

import 'tty.dart';
import 'tty_controls.dart' show TtySize;

/// Focus's command line — vim's last line, there only while it has something to say. Nothing is
/// drawn at the foot of Focus otherwise: the terminal is the screen.
///
/// Two modes, highest first:
/// - **message** — two seconds of `display-message`: black on yellow, or white on red for an error
///   (`✗ no match — tap an answer` has to be read over what it is about);
/// - **note** — an agent's question is open but has no keys to offer beside the mic (it takes
///   several answers, or is only partly on screen): `answer on screen`, in the asking yellow.
///
/// The answers themselves are not here: they are keycaps either side of the mic
/// (`terminal_page.dart`), so the mic never moves and nothing slabs over the dialog.
///
/// Drawn 2 rows tall on the terminal's grid, reaching [slop] further down into the home strip.
class CommandLine extends StatelessWidget {
  const CommandLine({super.key, this.slop = 0, this.promptNote, this.message});

  /// Whether there is anything to draw.
  bool get shows => promptNote != null || message != null;

  /// A question with no keys to offer: one line saying so.
  final String? promptNote;

  /// tmux's message line, for two seconds: black on yellow, or white on red for an error.
  final ({String text, bool error})? message;

  /// How far the line reaches below the drawn bar.
  final double slop;

  /// The drawn height: two terminal rows.
  static double heightOf(Tty tty) => 2 * tty.row;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
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
              color: message.error ? tty.theme.brightWhite : tty.theme.black,
            ),
          ),
        ),
      );
    }
    if (promptNote case final note?) {
      return SizedBox(
        height: bar + slop,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            height: bar,
            width: double.infinity,
            color: tty.ground,
            padding: const EdgeInsets.only(left: Tty.origin, right: Tty.origin),
            alignment: Alignment.centerLeft,
            child: TtyText(note, color: tty.yellow, size: TtySize.meta),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
