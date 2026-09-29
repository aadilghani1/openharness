/// Bundled, code-drawn artwork. This adapter never changes zoo state or asks
/// harnessd for a plate. Its keys are shared by Flutter and the native tab bar.
library;

import 'daemon_face.dart';
import 'roster.dart';

class IllustratedArt {
  const IllustratedArt._(this.stem, this.frames);

  static const timFrames = {
    'idle': 4,
    'work': 4,
    'need': 4,
    'done': 4,
    'fail': 1,
    'nap': 4,
    'back': 4,
    'boop': 4,
    'blink': 1,
  };
  static const eggFrames = {
    'p0': 4,
    'p1': 1,
    'p2': 1,
    'p3': 1,
    'p4': 4,
    'rock': 4,
    'burst': 4,
    'tumble': 4,
    'open': 1,
    'hatchling': 4,
  };
  static const eggKinds = {
    'first',
    'setup',
    'turn',
    'week',
    'marathon',
    'night',
    'history',
    'easter',
  };

  factory IllustratedArt.tim({
    String version = '0.1',
    DaemonMood mood = DaemonMood.idle,
    bool blink = false,
  }) {
    final age = switch (version) {
      '1.0' => 'young',
      '2.0' => 'adult',
      _ => 'baby',
    };
    final expression = blink && mood != DaemonMood.nap ? 'blink' : mood.name;
    return IllustratedArt._('tim_${age}_$expression', timFrames[expression]!);
  }

  factory IllustratedArt.egg({String kind = 'first', String stage = 'p0'}) {
    final shell = eggKinds.contains(kind) ? kind : 'first';
    final phase = eggFrames.containsKey(stage) ? stage : 'p0';
    return IllustratedArt._('egg_${shell}_$phase', eggFrames[phase]!);
  }

  final String stem;
  final int frames;
  String asset(int frame, {bool slot = false}) =>
      'assets/daemon-art/${slot ? 'slot' : 'portrait'}/${stem}_${frame % frames}.png';

  static IllustratedArt? forFace(DaemonFace face) {
    if (!face.visible) return null;
    if (face.showsDaemon) {
      if (face.def?.id != 'tim') return null;
      return IllustratedArt.tim(
        version: face.daemon!.version,
        mood: face.mood,
        blink: face.lid != null,
      );
    }
    final egg = face.eggArtwork;
    return egg == null ? null : IllustratedArt.egg(kind: egg.$1, stage: egg.$2);
  }

  static int frameForFace(DaemonFace face) => !face.motionEnabled
      ? 0
      : face.mood == DaemonMood.back
      ? face.t ~/ 130
      : face.mood == DaemonMood.work
      ? face.steps
      : 0;
}
