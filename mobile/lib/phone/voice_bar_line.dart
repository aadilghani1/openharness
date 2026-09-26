import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_line.dart';
import 'tty.dart';
import 'voice_input_controller.dart';

/// The status line while a voice take is live — one terminal row, where vim says `recording @q`:
/// ` ×   ● 0:04  ▁▃▅▇▆▃▁▃▅▂          → hn`.
///
/// `×` throws the take away. `●` and the clock are red while it records; the bars are the mic's
/// level, newest on the right; `→ hn` is the agent the take was started on and will go to — bound
/// at touch-down, never moved by a switch (switching agents ends the take). Transcribing, sending
/// and a take waiting to be sent again each get their own few words in the same place.
///
/// Nothing here animates on its own: it redraws as the mic's level moves, which is only while it
/// records.
class VoiceBarLine extends StatefulWidget {
  const VoiceBarLine({
    super.key,
    required this.voice,
    required this.agentName,
    this.slop = 0,
  });

  final VoiceInputController voice;
  final String agentName;
  final double slop;

  /// Whether the voice has anything to say on the bar.
  static bool shows(VoiceInputController voice) =>
      voice.isSending ||
      voice.notice != null ||
      voice.transcript.isNotEmpty ||
      voice.status == VoiceInputStatus.starting ||
      voice.status == VoiceInputStatus.listening ||
      voice.status == VoiceInputStatus.transcribing;

  @override
  State<VoiceBarLine> createState() => _VoiceBarLineState();
}

class _VoiceBarLineState extends State<VoiceBarLine> {
  static const _bars = ' ▁▂▃▄▅▆▇█';
  static const _kept = 12;
  final _levels = <double>[];

  @override
  void initState() {
    super.initState();
    widget.voice.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(VoiceBarLine old) {
    super.didUpdateWidget(old);
    if (!identical(old.voice, widget.voice)) {
      old.voice.level.removeListener(_onLevel);
      widget.voice.level.addListener(_onLevel);
    }
  }

  @override
  void dispose() {
    widget.voice.level.removeListener(_onLevel);
    super.dispose();
  }

  void _onLevel() {
    if (widget.voice.status != VoiceInputStatus.listening) return;
    setState(() {
      _levels.add(widget.voice.level.value.clamp(0.0, 1.0));
      if (_levels.length > _kept) _levels.removeAt(0);
    });
  }

  String get _wave => [
    for (final level in _levels)
      _bars[(level * (_bars.length - 1)).round().clamp(0, _bars.length - 1)],
  ].join().padLeft(_kept, _bars[1]);

  String get _clock {
    final length = widget.voice.takeLength;
    final seconds = length.inSeconds % 60;
    return '${length.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final voice = widget.voice;
    final bar = CommandLine.heightOf(tty);
    final List<InlineSpan> said;
    if (voice.notice case final notice?) {
      said = [
        TextSpan(
          text: notice.toLowerCase(),
          style: tty.style(color: tty.yellow),
        ),
      ];
    } else if (voice.isSending) {
      said = [
        TextSpan(
          text: 'sending…',
          style: tty.style(color: tty.faint),
        ),
      ];
    } else {
      said = switch (voice.status) {
        VoiceInputStatus.starting => [
          TextSpan(
            text: '● ',
            style: tty.style(color: tty.red),
          ),
          TextSpan(
            text: 'opening the mic…',
            style: tty.style(color: tty.faint),
          ),
        ],
        VoiceInputStatus.listening => [
          TextSpan(
            text: '● $_clock  ',
            style: tty.style(color: tty.red),
          ),
          TextSpan(
            text: _wave,
            style: tty.style(color: tty.text),
          ),
        ],
        VoiceInputStatus.transcribing => [
          TextSpan(
            text: 'transcribing…',
            style: tty.style(color: tty.yellow),
          ),
        ],
        _ => [
          TextSpan(
            text: 'not sent · ',
            style: tty.style(color: tty.red),
          ),
          TextSpan(
            text: 'tap the mic to send again',
            style: tty.style(color: tty.faint),
          ),
        ],
      };
    }
    return SizedBox(
      height: bar + widget.slop,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tty.ground,
          border: Border(top: BorderSide(color: tty.dim)),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: bar,
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Cancel the recording',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      voice.clear();
                    },
                    child: SizedBox(
                      width: Tty.origin + 5 * tty.cell,
                      height: bar + widget.slop,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          height: bar,
                          // SF Mono's `×` — it has no `✕`, and a fallback face would
                          // break the grid.
                          child: Center(child: TtyText('×', color: tty.text)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: said),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ),
                TtyText('→ ${widget.agentName}', color: tty.faint),
                const SizedBox(width: Tty.origin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
