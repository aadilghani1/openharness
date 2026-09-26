/// The zoo as the phone reads it: your daemons and eggs, account state the same
/// on every client (`daemons/README.md`, "The zoo"). The server is the
/// authority (`backend/src/lib/zoo.ts`); the phone is always signed in, so it
/// never draws, grants or levels anything itself. This is the wire shape, read
/// the way the desktop's `lib/daemons/zoo.dart` reads it: anything this roster
/// does not know is dropped, never an error.
library;

import 'roster.dart';

final _printable = RegExp(r'^[\x20-\x7e]*$');

/// A nickname: 1–24 printable ASCII characters.
bool validNickname(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    value.trim().length <= 24 &&
    _printable.hasMatch(value);

/// Bond level for [xp]: the highest threshold of `rules.bond.levels` reached.
int levelFor(DaemonRoster roster, int xp) {
  var level = 0;
  for (var i = 0; i < roster.rules.bondLevels.length; i++) {
    if (xp >= roster.rules.bondLevels[i]) level = i;
  }
  return level;
}

/// The version a bond level has grown into (`rules.bondForVersion`).
String versionFor(DaemonRoster roster, int level) {
  var version = roster.rules.versions.first;
  for (final v in roster.rules.versions) {
    if (level >= (roster.rules.bondForVersion[v] ?? 0)) version = v;
  }
  return version;
}

class ZooDaemon {
  const ZooDaemon({
    required this.id,
    required this.hatchedAt,
    required this.egg,
    this.shiny = false,
    this.nickname,
    this.bond = 0,
    this.xp = 0,
    this.version = '0.1',
  });
  final String id;
  final String hatchedAt;

  /// The kind of egg it came from (the card's "first egg").
  final String egg;
  final bool shiny;
  final String? nickname;
  final int bond, xp;
  final String version;

  /// `2026-09-26`, or null when the server sent no usable date.
  String? get hatchedDay {
    final at = DateTime.tryParse(hatchedAt);
    if (at == null) return null;
    final local = at.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Bond and version always follow xp; a daemon stored before xp reads the
  /// least xp its stored bond needs, so reading never lowers a level.
  static ZooDaemon? fromJson(Object? raw, DaemonRoster roster) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || roster.byId(id) == null) return null;
    final nickname = raw['nickname'];
    final levels = roster.rules.bondLevels;
    final storedBond = raw['bond'] is int ? raw['bond'] as int : 0;
    final xp = raw['xp'] is int && (raw['xp'] as int) >= 0
        ? raw['xp'] as int
        : levels[storedBond.clamp(0, levels.length - 1)];
    final bond = levelFor(roster, xp);
    return ZooDaemon(
      id: id,
      hatchedAt: raw['hatchedAt'] is String ? raw['hatchedAt'] as String : '',
      egg: raw['egg'] is String ? raw['egg'] as String : 'first',
      shiny: raw['shiny'] == true,
      nickname: nickname is String && validNickname(nickname)
          ? nickname.trim()
          : null,
      bond: bond,
      xp: xp,
      version: versionFor(roster, bond),
    );
  }
}

class ZooEgg {
  const ZooEgg({
    required this.id,
    required this.kind,
    required this.grantedAt,
    this.date,
  });
  final String id, kind, grantedAt;

  /// The local day a history egg was earned on.
  final String? date;

  static ZooEgg? fromJson(Object? raw, DaemonRoster roster) {
    if (raw is! Map) return null;
    final id = raw['id'], kind = raw['kind'], date = raw['date'];
    if (id is! String || id.isEmpty || kind is! String) return null;
    if (!roster.rules.eggs.containsKey(kind)) return null;
    return ZooEgg(
      id: id,
      kind: kind,
      grantedAt: raw['grantedAt'] is String ? raw['grantedAt'] as String : '',
      date: date is String ? date : null,
    );
  }
}

class Zoo {
  const Zoo({
    this.daemons = const [],
    this.eggs = const [],
    this.pair,
    this.habits = const [],
    this.firstEgg = false,
  });
  static const empty = Zoo();
  static const maxEggs = 12, maxDaemons = 64;

  final List<ZooDaemon> daemons;
  final List<ZooEgg> eggs;
  final String? pair;

  /// First-egg habits done (`rules.firstEgg.habits`).
  final List<String> habits;

  /// The first egg has been granted.
  final bool firstEgg;

  bool owns(String id) => daemons.any((d) => d.id == id);

  /// The daemon on the phone's chip: the pair (the first hatched with that
  /// id), else, defensively, the first.
  ZooDaemon? get paired =>
      daemons.where((d) => d.id == pair).firstOrNull ?? daemons.firstOrNull;

  /// Each roster id once, first hatched first: what the shelf shows.
  List<String> get ownedIds => {for (final d in daemons) d.id}.toList();

  Zoo copyWith({List<String>? habits, String? pair}) => Zoo(
    daemons: daemons,
    eggs: eggs,
    pair: pair ?? this.pair,
    habits: habits ?? this.habits,
    firstEgg: firstEgg,
  );

  static Zoo fromJson(Object? raw, DaemonRoster roster) {
    if (raw is! Map) return empty;
    final daemons = [
      for (final d in raw['daemons'] as List? ?? const [])
        ?ZooDaemon.fromJson(d, roster),
    ].take(maxDaemons).toList();
    final eggs = <ZooEgg>[];
    for (final e in raw['eggs'] as List? ?? const []) {
      final egg = ZooEgg.fromJson(e, roster);
      if (egg != null && !eggs.any((x) => x.id == egg.id)) eggs.add(egg);
    }
    final habitKeys = roster.rules.habits.map((h) => h.key).toSet();
    final pair = raw['pair'];
    return Zoo(
      daemons: daemons,
      eggs: eggs.take(maxEggs).toList(),
      pair: pair is String && daemons.any((d) => d.id == pair) ? pair : null,
      habits: <String>{
        for (final h in raw['habits'] as List? ?? const [])
          if (h is String && habitKeys.contains(h)) h,
      }.toList(),
      firstEgg: raw['firstEgg'] == true,
    );
  }
}

/// One egg opened by `zoo.hatch`: who came out, drawn on the server.
class ZooHatch {
  const ZooHatch({
    required this.eggId,
    required this.daemonId,
    required this.shiny,
  });
  final String eggId, daemonId;
  final bool shiny;

  static ZooHatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final eggId = raw['eggId'], daemonId = raw['daemonId'];
    if (eggId is! String || daemonId is! String) return null;
    return ZooHatch(
      eggId: eggId,
      daemonId: daemonId,
      shiny: raw['shiny'] == true,
    );
  }
}
