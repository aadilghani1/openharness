/// Filled daemons (`daemons/README.md`, "Plates" and "Plate colour"): every
/// frame `daemons/tools/bake.mjs` baked, read from the generated copy of
/// `daemons/plates.json`, and the colour rule every client draws them with
/// (bake.mjs `plateColor`). Clients never run a model: they print the baked
/// text. `test/daemons/plates_test.dart` checks the colours against
/// `frames.json` `plateColors`, cell by cell.
library;

import 'dart:convert';
import 'dart:ui' show Color;

import 'plates.g.dart';
import 'roster.dart';

/// The two widths a plate is baked at (`rules.plate.cols`): `portrait`
/// wherever a portrait shows (28 columns, at most 12 rows), `reveal` for the
/// hatch reveal and anywhere with room (56 columns, at most 24 rows).
enum PlateSize { portrait, reveal }

/// `plates.json`: `{ source, frameMs, daemons: { id: { portrait|reveal: {
/// version: { mood: [frame, ...] } } } } }`, a frame being rows joined by a
/// newline, every row and every frame of one daemon, size and version the
/// same size.
class DaemonPlates {
  DaemonPlates._(Map raw)
    : frameMs = (raw['frameMs'] as num? ?? 170).toInt(),
      _daemons = raw['daemons'] as Map? ?? const {};

  factory DaemonPlates.parse(String json) =>
      DaemonPlates._(jsonDecode(json) as Map);

  /// One frame of a loop shows this long (170 ms).
  final int frameMs;
  final Map _daemons;
  final _loops = <String, List<List<String>>>{};

  /// Whether [id] has baked plates.
  bool has(String id) => _daemons[id] is Map;

  /// [mood]'s loop for [id] at [size] and [version], each frame as rows (idle
  /// has 8 frames, every other mood 4). A version not baked draws as the
  /// first, like the roster's; a mood not baked loops idle. Empty for a
  /// daemon without plates. Rows are split once per loop and kept.
  List<List<String>> loop(
    String id,
    PlateSize size,
    String version,
    DaemonMood mood,
  ) => _loops['$id ${size.name} $version ${mood.name}'] ??= () {
    final versions = (_daemons[id] as Map?)?[size.name] as Map?;
    if (versions == null || versions.isEmpty) return const <List<String>>[];
    final moods = (versions[version] ?? versions.values.first) as Map;
    final frames = (moods[mood.name] ?? moods['idle']) as List? ?? const [];
    return [for (final f in frames) (f as String).split('\n')];
  }();

  /// Frame [index] of [mood]'s loop (it wraps); frame 0 is the still one
  /// (Reduce Motion, a card). Empty for a daemon without plates.
  List<String> frame(
    String id,
    PlateSize size,
    String version,
    DaemonMood mood, [
    int index = 0,
  ]) {
    final frames = loop(id, size, version, mood);
    return frames.isEmpty ? const [] : frames[index % frames.length];
  }
}

/// Every plate, parsed once and only when a plate is first drawn: a
/// top-level final is initialised on first use.
final daemonPlates = DaemonPlates.parse(daemonPlatesJson);

/// The terminal background `frames.json` `plateColors` were computed on.
const plateReferenceBackground = Color(0xff0c0c0c);

const _white = Color(0xffffffff);

int _channel(Color c, int shift) => (c.toARGB32() >> shift) & 0xff;

/// `mix(a, b, t)` as bake.mjs mixes: per RGB channel, rounded.
Color plateMix(Color a, Color b, double t) {
  int mix(int shift) {
    final v = _channel(a, shift);
    return (v + (_channel(b, shift) - v) * t).round();
  }

  return Color.fromARGB(255, mix(16), mix(8), mix(0));
}

/// `#rrggbb`, as `frames.json` writes a colour.
String plateHex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// The gradient a plate is drawn in: its shiny one when [shiny] (every
/// shiny in drop init is gold). Null for a daemon drawn in line art.
DaemonGradient? plateGradient(DaemonDef d, {bool shiny = false}) =>
    shiny ? d.shinyGradient ?? d.gradient : d.gradient;

/// How one plate is coloured on one background (bake.mjs `plateColor`):
/// row r of R rows takes `mix(top, bottom, r / (R - 1))`; each glyph takes
/// its brightness from `rules.plate.ink`, and at most 1 mixes from
/// [background] toward the row's colour (`.` is faint, `#` is the colour
/// itself) while above 1 mixes on toward [burn] by the excess (`@` burns).
/// Spaces, and glyphs with no ink level, are not drawn.
class PlateInk {
  PlateInk(
    this.roster,
    this.gradient, {
    this.background = plateReferenceBackground,
    this.burn = _white,
  });

  final DaemonRoster roster;
  final DaemonGradient gradient;

  /// What faint glyphs mix from: the colour the plate is drawn on.
  final Color background;

  /// What a glyph brighter than its row mixes toward: white on a dark
  /// background.
  final Color burn;
  final _cache = <(int, int, String), Color?>{};

  /// The colour of row [r] of a plate [rows] tall.
  Color row(int rows, int r) =>
      plateMix(gradient.top, gradient.bottom, rows > 1 ? r / (rows - 1) : 0);

  /// The colour of glyph [ch] on row [r] of a plate [rows] tall, or null
  /// where nothing is drawn.
  Color? glyph(int rows, int r, String ch) =>
      _cache.putIfAbsent((rows, r, ch), () {
        final level = roster.rules.plate?.ink[ch];
        if (level == null) return null;
        final colour = row(rows, r);
        return level > 1
            ? plateMix(colour, burn, level - 1)
            : plateMix(background, colour, level);
      });

  /// The soft glow a client may draw around a plate: its bottom colour.
  Color get glow => gradient.bottom;
}

/// The colour of one character of a plate, exactly as bake.mjs `plateColor`
/// computes it (on the reference background unless told otherwise). Null
/// for a space or a daemon drawn in line art.
Color? plateColor(
  DaemonRoster roster,
  DaemonDef d,
  int rows,
  int r,
  String ch, {
  Color background = plateReferenceBackground,
  bool shiny = false,
}) {
  final gradient = plateGradient(d, shiny: shiny);
  if (gradient == null) return null;
  return PlateInk(roster, gradient, background: background).glyph(rows, r, ch);
}
