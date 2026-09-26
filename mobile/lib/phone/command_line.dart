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
            // Yellow to the screen's edge: the keys' touch runs down through the home strip, so
            // the colour does too — a bar that stopped short read as a strip of black under it.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: bar + slop,
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
                        child: _AnswerKey(
                          label: keys[i].label,
                          ink: ink,
                          bar: bar,
                          slop: slop,
                          onTap: keys[i].onTap,
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

/// One answer on the prompt bar. It darkens under the finger on the way DOWN, the way a key does,
/// so the answer reads as taken before the dialog has even closed.
class _AnswerKey extends StatefulWidget {
  const _AnswerKey({
    required this.label,
    required this.ink,
    required this.bar,
    required this.slop,
    required this.onTap,
  });

  final String label;
  final Color ink;
  final double bar;
  final double slop;
  final VoidCallback onTap;

  @override
  State<_AnswerKey> createState() => _AnswerKeyState();
}

class _AnswerKeyState extends State<_AnswerKey> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _set(true),
    onTapCancel: () => _set(false),
    onTapUp: (_) => _set(false),
    onTap: () {
      HapticFeedback.selectionClick();
      widget.onTap();
    },
    child: SizedBox(
      height: widget.bar + widget.slop,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: widget.bar,
          color: _down ? Colors.black.withValues(alpha: 0.18) : null,
          alignment: Alignment.center,
          child: TtyText(
            widget.label,
            color: widget.ink,
            weight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
