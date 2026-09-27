import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show TerminalTheme;

import '../daemons/plates.dart';
import '../daemons/render.dart';
import '../daemons/roster.dart';
import 'daemon_slot.dart';

/// A daemon's portrait wherever one shows: the panel's zoo, the hatch
/// reveal, a duplicate's merge and a level-up.
///
/// A filled daemon (README, "Plates") prints its baked plate at [size], each
/// glyph in the plate colour ([daemonPlateInk]) with a soft glow in its
/// bottom colour, and steps through [mood]'s loop, a frame every `frameMs`
/// (170 ms), while [animate] is on and the page can move: Reduce Motion, a
/// paused ticker (the panel off screen) or [animate] off (a background
/// window, the Motion setting) show frame 0. Any other daemon draws its line
/// portrait in its one colour, as it always has, its parts moving with [t],
/// [lid] and [motion].
///
/// [silhouette] draws every glyph as `#` in [style]'s colour; [rows] draws
/// given rows (a morph between versions) in the daemon's colours, still.
class DaemonPortrait extends StatefulWidget {
  const DaemonPortrait({
    super.key,
    required this.roster,
    required this.def,
    required this.version,
    required this.style,
    required this.theme,
    this.mood = DaemonMood.idle,
    this.size = PlateSize.portrait,
    this.shiny = false,
    this.animate = false,
    this.background,
    this.silhouette = false,
    this.rows,
    this.t = 0,
    this.lid,
    this.motion = false,
    this.textKey,
    this.semanticsLabel,
  });

  final DaemonRoster roster;
  final DaemonDef def;
  final String version;

  /// The ink: font, features and line height. A silhouette takes its colour.
  final TextStyle style;
  final TerminalTheme theme;
  final DaemonMood mood;
  final PlateSize size;
  final bool shiny;
  final bool animate;

  /// What the portrait is drawn on, which faint glyphs mix from: the
  /// daemon's backdrop or the terminal's background by default.
  final Color? background;
  final bool silhouette;
  final List<String>? rows;
  final int t;
  final String? lid;
  final bool motion;
  final Key? textKey;
  final String? semanticsLabel;

  @override
  State<DaemonPortrait> createState() => _DaemonPortraitState();
}

class _DaemonPortraitState extends State<DaemonPortrait> {
  Timer? _timer;
  int _tick = 0;

  List<List<String>> get _loop => daemonPlates.loop(
    widget.def.id,
    widget.size,
    widget.version,
    widget.mood,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(DaemonPortrait old) {
    super.didUpdateWidget(old);
    // A new mood starts its loop at the beginning.
    if (old.mood != widget.mood ||
        old.def.id != widget.def.id ||
        old.version != widget.version ||
        old.size != widget.size) {
      _tick = 0;
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Whether the loop may run now: a plate, asked to move, on a page that
  /// can move (no Reduce Motion, a live ticker), with more than one frame.
  bool get _moving =>
      widget.animate &&
      widget.def.plate &&
      widget.rows == null &&
      !widget.silhouette &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
      TickerMode.valuesOf(context).enabled &&
      _loop.length > 1;

  void _schedule() {
    final moving = _moving;
    if (moving == (_timer != null)) return;
    _timer?.cancel();
    _timer = null;
    if (!moving) {
      _tick = 0;
      return;
    }
    _timer = Timer.periodic(Duration(milliseconds: daemonPlates.frameMs), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final label = w.semanticsLabel;
    if (!w.def.plate) {
      final rows =
          w.rows ??
          renderPortrait(
            w.roster,
            w.def,
            w.version,
            w.mood,
            t: w.t,
            lid: w.lid,
            motion: w.motion,
          );
      return Text(
        (w.silhouette ? rows.map(silhouette) : rows).join('\n'),
        key: w.textKey,
        semanticsLabel: label,
        style: w.silhouette
            ? w.style
            : w.style.copyWith(
                color: daemonColor(w.def, w.theme, shiny: w.shiny),
              ),
      );
    }
    final loop = _loop;
    final rows =
        w.rows ?? (loop.isEmpty ? const <String>[] : loop[_tick % loop.length]);
    if (w.silhouette) {
      return Text(
        rows.map(silhouette).join('\n'),
        key: w.textKey,
        semanticsLabel: label,
        style: w.style,
      );
    }
    final ink = daemonPlateInk(
      w.roster,
      w.def,
      w.theme,
      shiny: w.shiny,
      background: w.background,
    )!;
    // The glow: one soft shadow in the bottom colour under every glyph.
    final size = w.style.fontSize ?? 13;
    final style = w.style.copyWith(
      shadows: [
        Shadow(color: ink.glow.withValues(alpha: .45), blurRadius: size * .8),
      ],
    );
    // Only the plate repaints on each frame of its loop.
    return RepaintBoundary(
      child: Text.rich(
        TextSpan(children: plateSpans(rows, ink, style)),
        key: w.textKey,
        semanticsLabel: label,
        style: style,
      ),
    );
  }
}
