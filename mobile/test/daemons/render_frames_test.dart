// The phone's Dart renderer against the reference renderer's pinned frames
// (daemons/frames.json, written by daemons/tools/generate.mjs): every sprite,
// portrait, status cell, card and banner, byte for byte, so the phone draws
// exactly what hn, the desktop and the lookbook draw.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/daemons/card.dart';
import 'package:harness_mobile/daemons/render.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';

void main() {
  final frames =
      jsonDecode(File('../daemons/frames.json').readAsStringSync()) as Map;
  final roster = daemonRoster;
  final printable = RegExp(r'^[\x20-\x7e]*$');

  test('the generated roster parses and matches roster.json', () {
    final source =
        jsonDecode(File('../daemons/roster.json').readAsStringSync()) as Map;
    expect(roster.daemons.map((d) => d.id), [
      for (final d in source['daemons'] as List) (d as Map)['id'],
    ]);
    expect(roster.rules.statusCells, 8);
    expect(roster.rules.habits.map((h) => h.key), contains('elsewhere'));
    // Economy v2: the setup egg, duplicate and overflow xp, shiny colours and
    // drop dates, all read from the roster rather than written down here.
    final rules = source['rules'] as Map;
    expect(roster.rules.setupEggNeed, (rules['setupEgg'] as Map)['need']);
    expect(roster.rules.duplicateXp, rules['duplicateXp']);
    expect(roster.rules.overflowXp, rules['overflowXp']);
    expect(roster.rules.eggs['setup']!.look, r'\_$_/');
    for (final (i, raw) in (source['daemons'] as List).indexed) {
      final shiny = (raw as Map)['shiny'] as Map;
      expect(roster.daemons[i].shinyHex, shiny['hex']);
      expect(
        roster.daemons[i].colorFor(shiny: true),
        isNot(roster.daemons[i].color),
      );
    }
    for (final (i, raw) in (source['drops'] as List).indexed) {
      expect(roster.drops[i].announce, (raw as Map)['announce']);
      expect(roster.drops[i].release, raw['release']);
    }
  });

  test(
    'a drop is announced, then released, on UTC days (card.mjs dropState)',
    () {
      final unix = roster.drop('unix')!;
      expect(
        unix.stateAt(DateTime.utc(2026, 9, 11, 23, 59, 59)),
        DropState.hidden,
      );
      expect(unix.stateAt(DateTime.utc(2026, 9, 12)), DropState.announced);
      expect(
        unix.stateAt(DateTime.utc(2026, 9, 25, 23, 59, 59)),
        DropState.announced,
      );
      expect(unix.stateAt(DateTime.utc(2026, 9, 26)), DropState.released);
      // A drop without dates is out.
      expect(
        const DaemonDrop('x', 2, 'x').stateAt(DateTime.utc(2000)),
        DropState.released,
      );
      expect(shelfDrops(roster, DateTime.utc(2026, 9, 1)), isEmpty);
      expect(shelfDrops(roster, DateTime.utc(2026, 9, 20)).single.id, 'unix');
    },
  );

  test('a card carries its serial; a guest\'s daemon has none', () {
    final tim = roster.byId('tim')!;
    final framed = (frames['cards'] as List).cast<Map>().firstWhere(
      (f) => f['id'] == 'tim' && f['version'] == '2.0' && f['serial'] == 42,
    );
    // The card of a daemon you own is card.mjs's card with its own facts.
    final mine = ZooDaemon.fromJson({
      'id': 'tim',
      'hatchedAt': '2026-09-26T12:00:00Z',
      'egg': 'first',
      'shiny': true,
      'nickname': 'pip',
      'xp': 600,
      'serial': 42,
    }, roster)!;
    final lines = ownedCardLines(roster, tim, mine);
    expect(lines, [for (final l in framed['out'] as List) l as String]);
    expect(lines.join('\n'), contains('pip the tim 2.0  #0042'));
    expect(serialLabel(7), '#0007');

    final seeded = ZooDaemon.fromJson({
      'id': 'tim',
      'hatchedAt': '2026-09-26T12:00:00Z',
      'egg': 'first',
      'xp': 600,
      'serial': 42,
      'origin': 'local',
    }, roster)!;
    expect(
      ownedCardLines(roster, tim, seeded).join('\n'),
      isNot(contains('#00')),
    );
    // The portrait rows are the ones a card colours.
    final rows = cardPortraitRows(roster, tim, '2.0');
    final portrait = renderPortrait(
      roster,
      tim,
      '2.0',
      DaemonMood.idle,
      motion: false,
    );
    expect(rows.to - rows.from, portrait.length);
    for (final (i, line) in portrait.indexed) {
      expect(lines[rows.from + i], contains(line));
    }
  });

  test('every sprite frame matches the reference renderer', () {
    final sprites = frames['sprites'] as List;
    expect(sprites, hasLength(greaterThan(900)));
    for (final raw in sprites) {
      final f = raw as Map;
      final d = roster.byId(f['id'] as String)!;
      final out = renderSprite(
        roster,
        d,
        roster.versionIndex(f['v'] as String),
        daemonMoodNamed(f['mood'] as String)!,
        t: f['t'] as int,
        lid: f['lid'] as String?,
      );
      expect(
        out,
        f['out'],
        reason: '${f['id']} ${f['v']} ${f['mood']} t=${f['t']} lid=${f['lid']}',
      );
    }
  });

  test('every portrait frame matches the reference renderer', () {
    final portraits = frames['portraits'] as List;
    expect(portraits, hasLength(greaterThan(400)));
    for (final raw in portraits) {
      final f = raw as Map;
      final d = roster.byId(f['id'] as String)!;
      final out = renderPortrait(
        roster,
        d,
        f['v'] as String,
        daemonMoodNamed(f['mood'] as String)!,
        t: f['t'] as int,
      );
      expect(out, [
        for (final l in f['out'] as List) l as String,
      ], reason: '${f['id']} ${f['v']} ${f['mood']} t=${f['t']}');
    }
  });

  test('every status cell matches, centred on the base sprite', () {
    final cells = frames['cells'] as List;
    expect(cells, hasLength(greaterThan(400)));
    for (final raw in cells) {
      final f = raw as Map;
      final d = roster.byId(f['id'] as String)!;
      final vi = roster.versionIndex(f['v'] as String);
      final sprite = renderSprite(
        roster,
        d,
        vi,
        daemonMoodNamed(f['mood'] as String)!,
        t: f['t'] as int,
      );
      final cell = statusCell(roster, sprite, baseWidth(roster, d, vi));
      expect(
        cell,
        f['out'],
        reason: '${f['id']} ${f['v']} ${f['mood']} t=${f['t']}',
      );
    }
  });

  test('every card matches card.mjs', () {
    final cards = frames['cards'] as List;
    expect(cards, hasLength(roster.daemons.length * 6));
    for (final raw in cards) {
      final f = raw as Map;
      final d = roster.byId(f['id'] as String)!;
      final out = cardLines(
        roster,
        d,
        version: f['version'] as String,
        shiny: f['shiny'] == true,
        serial: f['serial'] as int?,
        nickname: f['nickname'] as String?,
        hatched: f['hatched'] as String?,
        egg: f['egg'] as String?,
      );
      expect(out, [
        for (final l in f['out'] as List) l as String,
      ], reason: '${f['id']} ${f['version']} shiny=${f['shiny']}');
      expect(out.every((l) => l.length == cardWidth), isTrue);
      expect(out.every(printable.hasMatch), isTrue);
    }
    // Secrets sit outside the numbered set.
    expect(cardNumber(roster, roster.byId('tim')!), '#01/09');
    expect(cardNumber(roster, roster.byId('grue')!), '#S/09');
  });

  test('the generated banner copy matches banner.json', () {
    final source =
        jsonDecode(File('../daemons/banner.json').readAsStringSync()) as Map;
    expect(daemonBanner.rows, source['rows']);
    expect(daemonBanner.gap, source['gap']);
    expect(daemonBanner.glyphs, source['glyphs']);
  });

  test('every banner matches renderBanner in render.mjs', () {
    final banners = frames['banners'] as List;
    expect(banners, hasLength(roster.daemons.length));
    for (final raw in banners) {
      final f = raw as Map;
      final out = renderBanner(daemonBanner, f['id'] as String);
      expect(out, [
        for (final l in f['out'] as List) l as String,
      ], reason: f['id'] as String);
      expect(out.every(printable.hasMatch), isTrue, reason: f['id'] as String);
    }
    expect(renderBanner(daemonBanner, 'tim'), [
      ' _     _',
      '| |_  (_)  _ __',
      "|  _| | | | '  \\",
      ' \\__| |_| |_|_|_|',
    ]);
    // Upper case draws as lower; a character the face lacks is a space.
    expect(
      renderBanner(daemonBanner, 'TIM'),
      renderBanner(daemonBanner, 'tim'),
    );
    expect(
      renderBanner(daemonBanner, 'i#i'),
      renderBanner(daemonBanner, 'i i'),
    );
    expect(renderBanner(daemonBanner, ''), isEmpty);
  });

  test('the shelf matches card.mjs shelfLines', () {
    expect(shelfLines(roster, shelfEntries(['tim', 'vim', 'grue'])), [
      'zoo: drop 1 unix  2/9  +secret',
      '',
      r'\[o|o]/   [ ? ]     [ ? ]     [ ? ]     < o_o >_',
      'tim       #02       #03       #04       vim',
      '',
      '[ ? ]     [ ? ]     [ ? ]     [ ? ]     .   .',
      '#06       #07       #08       #09       grue',
    ]);
    expect(shelfLines(roster, const []), [
      'zoo: drop 1 unix  0/9',
      '',
      '[ ? ]     [ ? ]     [ ? ]     [ ? ]     [ ? ]',
      '#01       #02       #03       #04       #05',
      '',
      '[ ? ]     [ ? ]     [ ? ]     [ ? ]     [ ! ]',
      '#06       #07       #08       #09       secret',
    ]);
    expect(fencedCard(['a', 'b']), '```\na\nb\n```');
  });

  test(
    'the shelf counts duplicates and shows announced drops, as card.mjs',
    () {
      // node daemons/tools/card.mjs --shelf 'tim*x2,vim,grue x4'
      final released = DateTime.utc(2026, 9, 27);
      expect(
        shelfLines(roster, const [
          ShelfEntry('tim', shiny: true, dupes: 1),
          ShelfEntry('vim'),
          ShelfEntry('grue', dupes: 3),
        ], now: released),
        [
          'zoo: drop 1 unix  2/9  +secret',
          '',
          r'\[o|o]/   [ ? ]     [ ? ]     [ ? ]     < o_o >_',
          'tim x2    #02       #03       #04       vim',
          '',
          '[ ? ]     [ ? ]     [ ? ]     [ ? ]     .   .',
          '#06       #07       #08       #09       grue x4',
        ],
      );
      final cells = shelfCells(roster, const [
        ShelfEntry('tim', shiny: true, dupes: 1),
      ], now: released);
      expect(cells.first.shiny, isTrue);
      expect(cells.first.count, 2);
      // Announced, not released: silhouettes of the 0.1 sprites, the release
      // date, and what you own does not show yet.
      expect(
        shelfLines(
          roster,
          shelfEntries(['tim']),
          now: DateTime.utc(2026, 9, 25, 23, 59, 59),
        ),
        [
          'zoo: drop 1 unix  out 2026-09-26',
          '',
          '## ##     #####     ## ##     #####     # ###',
          '#01       #02       #03       #04       #05',
          '',
          '# ####    #####     #####     #######   [ ! ]',
          '#06       #07       #08       #09       secret',
        ],
      );
      final announced = shelfCells(
        roster,
        const [],
        now: DateTime.utc(2026, 9, 20),
      );
      expect(announced.where((c) => c.silhouette), hasLength(9));
      expect(announced.any((c) => c.owned), isFalse);
      // Not announced yet: shown nowhere.
      expect(
        shelfLines(roster, const [], now: DateTime.utc(2026, 9, 1)),
        isEmpty,
      );
      expect(
        shelfCells(roster, const [], now: DateTime.utc(2026, 9, 1)),
        isEmpty,
      );
    },
  );

  test('nest stages follow habits done, as render.mjs nestStage', () {
    final nests = (frames['nests'] as List).cast<Map>();
    expect(nests, isNotEmpty);
    expect(
      [
        for (final n in nests)
          nestFor(roster, (n['habits'] as List).cast<String>()),
      ],
      [for (final n in nests) n['out'] as String],
    );
  });

  test('the reveal pieces keep their shape', () {
    for (final frame in [
      eggFrame(roster),
      eggFrame(roster, offset: -1),
      eggFrame(roster, offset: 1, crack: 1),
      eggFrame(roster, crack: 2),
      eggPopFrame(roster),
    ]) {
      expect(frame.split('\n').every((r) => r.length == 18), isTrue);
    }
    expect(silhouette('[oo]'), '####');
    expect(silhouette('o   o'), '#   #');
    expect(
      rarityStamp(roster, roster.byId('vim')!, shiny: true),
      '[ * SHINY * RARE ]  #05/09',
    );
  });

  test('a new version morphs in three quick frames', () {
    final tim = roster.byId('tim')!;
    String at(int v) => renderSprite(roster, tim, v, DaemonMood.idle);
    expect(versionMorph(at(0), at(1)), ['## ##', '#####', '[o|o]']);
    expect(versionMorph(at(1), at(2)), ['#####', '#######', r'\[o|o]/']);
  });
}
