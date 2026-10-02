import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The scroll physics of a full-screen program's scroll — the alternate screen, where the phone has
/// no history of its own and a scroll is wheel events sent to the machine (`TerminalView`'s
/// `altBufferScrollPhysics`). A drag is the platform's own; a fling is short.
///
/// ⚠️ **A fling here coasted for seconds, sending the program a wheel for every line it passed.**
/// That scrollable has no ends — its extents are infinite — so a platform fling never meets a
/// boundary and runs until friction alone stops it. Measured on Claude Code (2026-10-02): a flick of a tenth of a second coasted 2–5 s and sent 150–450 wheels, 97% of
/// them after the finger had lifted; the program, a few hundred milliseconds behind, kept redrawing
/// a screen that jumped for seconds after the person had stopped.
///
/// Here the fling decays at [decayPerSecond] from a speed held to [maxVelocity]: at most
/// `maxVelocity / decayPerSecond` pixels, nearly all of it in the first quarter second. While the
/// finger is down nothing changes — each line dragged is still one wheel.
///
/// Only where the extents are infinite. Anywhere else — reused on a scrollable with ends — it
/// defers to the platform, so a bounded scroll keeps its own fling and its overscroll.
class RemoteScrollPhysics extends ScrollPhysics {
  const RemoteScrollPhysics({super.parent});

  /// How fast the fling's speed falls away: it keeps `e^-decayPerSecond` of its speed after a
  /// second, which at 10 is gone in effect within a quarter of one.
  static const decayPerSecond = 10.0;

  /// The fastest a fling starts, in logical pixels a second — with [decayPerSecond], a fling that
  /// carries at most 300 px: some twenty lines of wheels, however hard the flick.
  static const maxVelocity = 3000.0;

  @override
  RemoteScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      RemoteScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.minScrollExtent.isFinite ||
        position.maxScrollExtent.isFinite) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity) return null;
    return FrictionSimulation(
      math.exp(-decayPerSecond),
      position.pixels,
      velocity.clamp(-maxVelocity, maxVelocity).toDouble(),
      tolerance: tolerance,
    );
  }
}
