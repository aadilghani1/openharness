import 'package:flutter/material.dart';

import 'tty.dart';
import 'tty_controls.dart' show TtySize;
import 'voice_input_controller.dart';

/// What the mic is doing, said beside it.
///
/// While a take records, [VoiceTakeClock] sits on the mic's right: `● 0:04 ▁▃▅▇▆▃`, red, the
/// mic's level newest on the right. Everything else a take goes through — opening the mic,
/// transcribing, sending, a take waiting to be sent again — is a few words on the line above the
/// mic ([voiceStatus]). The take goes to the harness on screen, which its title already names.
abstract final class VoiceLine {
  /// Whether the voice has anything to say or show.
  static bool shows(VoiceInputController voice) =>
      voice.isSending ||
      voice.notice != null ||
      voice.transcript.isNotEmpty ||
      voice.status == VoiceInputStatus.starting ||
      voice.status == VoiceInputStatus.listening ||
      voice.status == VoiceInputStatus.transcribing;

  /// Whether a take is being recorded right now: the clock shows, and esc throws it away.
  static bool recording(VoiceInputController voice) =>
      voice.status == VoiceInputStatus.starting ||
      voice.status == VoiceInputStatus.listening;
}

/// The words for the line above the mic, or null while it records (the clock says that) or has
/// nothing to say.
({String text, Color color})? voiceStatus(VoiceInputController voice, Tty tty) {
  if (voice.notice case final notice?) {
    return (text: notice.toLowerCase(), color: tty.yellow);
  }
  if (voice.isSending) return (text: 'sending…', color: tty.faint);
  return switch (voice.status) {
    VoiceInputStatus.starting => (text: 'opening the mic…', color: tty.faint),
    VoiceInputStatus.listening => null,
    VoiceInputStatus.transcribing => (text: 'transcribing…', color: tty.yellow),
    _ when VoiceLine.shows(voice) => (
      text: 'not sent · tap the mic again',
      color: tty.red,
    ),
    _ => null,
  };
}

/// `● 0:04 ▁▃▅▇▆▃` — the take's length and the mic's level, beside the mic while it records.
///
/// Nothing here animates on its own: it redraws as the mic's level moves, which is only while it
/// records.
class VoiceTakeClock extends StatefulWidget {
  const VoiceTakeClock({super.key, required this.voice});

  final VoiceInputController voice;

  @override
  State<VoiceTakeClock> createState() => _VoiceTakeClockState();
}

class _VoiceTakeClockState extends State<VoiceTakeClock> {
  static const _bars = ' ▁▂▃▄▅▆▇█';
  static const _kept = 6;
  final _levels = <double>[];

  @override
  void initState() {
    super.initState();
    widget.voice.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(VoiceTakeClock old) {
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
    return ExcludeSemantics(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '● $_clock ',
              style: tty.style(color: tty.red, size: TtySize.meta),
            ),
            TextSpan(
              text: _wave,
              style: tty.style(color: tty.text, size: TtySize.meta),
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );
  }
}
