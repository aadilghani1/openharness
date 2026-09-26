// The daemon where a phone meets it: the chip in the header, its sheet, and
// the full-screen hatch reveal — on a 320pt phone and with large text too.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/daemons/card.dart';
import 'package:harness_mobile/daemons/daemon_face.dart';
import 'package:harness_mobile/daemons/daemon_lines.dart';
import 'package:harness_mobile/daemons/render.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';
import 'package:harness_mobile/daemons/zoo_client.dart';
import 'package:harness_mobile/phone/daemon_chip.dart';
import 'package:harness_mobile/phone/daemon_hatch.dart';
import 'package:harness_mobile/phone/daemon_scope.dart';
import 'package:harness_mobile/phone/daemon_sheet.dart';
import 'package:harness_mobile/phone/daemon_style.dart';
import 'package:harness_mobile/state/app_state.dart';

import '../agent_pager_fixture.dart';
import 'zoo_fixture.dart';

/// Every platform call a test cares about: the clipboard and the haptics.
class _Platform {
  String? clipboard;
  final haptics = <String>[];

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String?;
          case 'HapticFeedback.vibrate':
            haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }
}

Map<String, dynamic> _nest({
  List<String> habits = const [],
  bool egg = false,
}) => {
  'daemons': const [],
  'eggs': [
    if (egg) {'id': 'e0', 'kind': 'first', 'grantedAt': ''},
  ],
  'pair': null,
  'habits': habits,
  'firstEgg': egg,
};

Future<AppNotifier> _pump(
  WidgetTester tester,
  FakeZooBackend backend, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final app = pagerApp(PagerConn());
  addTearDown(app.dispose);
  app.api = ZooApi(backend);
  app.zoo.ensure();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: DaemonHost(
        notifier: app,
        child: const Scaffold(
          body: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [DaemonChip(), SizedBox(width: 14)],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return app;
}

/// The sheet's own scroll view.
final _sheetScroll = find
    .descendant(
      of: find.byKey(const ValueKey('daemon-sheet')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('daemon-chip')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Walk the reveal to its card, a frame at a time.
Future<void> _toCard(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    if (find.byKey(const ValueKey('daemon-hatch-card')).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('the reveal never reached its card');
}

void main() {
  late FakeZooBackend backend;
  setUp(() => backend = FakeZooBackend());

  testWidgets('the chip draws the paired sprite and says who it is', (
    tester,
  ) async {
    await _pump(tester, backend);
    final chip = find.byKey(const ValueKey('daemon-chip'));
    expect(chip, findsOneWidget);
    expect(find.text(r'  [o o]   '), findsOneWidget);
    expect(
      tester.getSemantics(chip).label,
      'tim, tim 0.1, content, 1 egg waiting',
    );
    // Eggs are waiting: a dot on its corner.
    expect(find.byKey(const ValueKey('daemon-chip-eggs')), findsOneWidget);
  });

  testWidgets('no chip outside the shell, or before the zoo answers', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DaemonChip()));
    expect(find.byKey(const ValueKey('daemon-chip')), findsNothing);

    final app = pagerApp(PagerConn());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DaemonHost(notifier: app, child: const DaemonChip()),
      ),
    );
    expect(find.byKey(const ValueKey('daemon-chip')), findsNothing);
  });

  testWidgets('a tap boops it and opens its sheet', (tester) async {
    final platform = _Platform()..install(tester);
    await _pump(tester, backend);
    await _openSheet(tester);
    expect(platform.haptics, contains('HapticFeedbackType.selectionClick'));
    expect(find.byKey(const ValueKey('daemon-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('daemon-name')), findsOneWidget);
    // Booped: the portrait's eyes are wide.
    final portrait = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('daemon-portrait')),
        matching: find.byType(Text),
      ),
    );
    expect(portrait.data, contains('O'));
    await tester.pump(const Duration(seconds: 1));
    // The line is the truth: nothing is waiting on this phone, and tim's idle template has no slots.
    expect(find.byKey(const ValueKey('daemon-line')), findsOneWidget);
    expect(find.textContaining('all quiet. no alerts.'), findsOneWidget);
    expect(find.textContaining('screen -> tmux -> tim'), findsOneWidget);
    expect(find.textContaining('zoo: drop 1 unix  2/9'), findsOneWidget);
    expect(find.text('Hatch'), findsOneWidget);
  });

  testWidgets('only a need or a failure takes the yellow message line', (
    tester,
  ) async {
    await _pump(tester, backend);
    await _openSheet(tester);
    final line = find.byKey(const ValueKey('daemon-line'));
    bool alert() => find
        .descendant(
          of: line,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == DaemonInk.yellow,
          ),
        )
        .evaluate()
        .isNotEmpty;
    Color? colour() => tester
        .widget<Text>(find.descendant(of: line, matching: find.byType(Text)))
        .style
        ?.color;

    // Booped: it is talking about itself, which needs nobody.
    expect(alert(), isFalse);
    await tester.pump(const Duration(seconds: 1));
    final face = tester.state<DaemonHostState>(find.byType(DaemonHost)).face;
    for (final (watch, mood, loud) in [
      (const DaemonWatch(), DaemonMood.idle, false),
      (const DaemonWatch(working: {'m/a'}), DaemonMood.work, false),
      (const DaemonWatch(needs: {'m/a#q'}), DaemonMood.need, true),
      (const DaemonWatch(failing: {'m/a'}), DaemonMood.fail, true),
      (const DaemonWatch(), DaemonMood.idle, false),
    ]) {
      face.sync(watch);
      await tester.pump();
      expect(face.mood, mood);
      expect(alert(), loud, reason: mood.name);
      // Content is dim text; an alert is dark on the yellow line.
      expect(
        colour(),
        loud ? DaemonInk.pitch : DaemonInk.dim,
        reason: mood.name,
      );
    }
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the shelf pairs a daemon you own', (tester) async {
    final app = await _pump(tester, backend);
    await _openSheet(tester);
    final vim = find.byKey(const ValueKey('daemon-shelf-vim'));
    await tester.ensureVisible(vim);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(vim).label, 'vim');
    await tester.tap(vim);
    await tester.pump();
    expect(app.zoo.paired!.id, 'vim');
    await app.zoo.settle();
    expect(backend.written, [
      {'op': 'zoo.pair', 'id': 'vim'},
    ]);
    await tester.pump();
    expect(tester.getSemantics(vim).label, 'vim, paired');
    // Empty slots are numbered; the secret is a `[ ! ]`.
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daemon-shelf-unix-#03')))
          .label,
      'Number 03, not hatched yet',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daemon-shelf-unix-secret')))
          .label,
      'A secret, not found yet',
    );
  });

  testWidgets('before any daemon the sheet is the nest and its habits', (
    tester,
  ) async {
    backend.zoo = _nest(habits: const ['turn', 'split', 'find']);
    await _pump(tester, backend);
    // A turn and two more: the egg is ready to arrive.
    expect(find.text(r' \_o.o_/  '), findsOneWidget);
    await _openSheet(tester);
    expect(find.text('A daemon is incubating'), findsOneWidget);
    expect(find.text('[x]'), findsNWidgets(3));
    expect(find.text('[ ]'), findsNWidgets(5));
    expect(find.text('Hatch'), findsNothing);
  });

  testWidgets('hatching: wobble, crack, silhouette, colour, banner, card', (
    tester,
  ) async {
    final platform = _Platform()..install(tester);
    backend.zoo = _nest(
      habits: const ['turn', 'split', 'find', 'machine', 'store'],
      egg: true,
    );
    backend.nextDaemon = 'tim';
    final app = await _pump(tester, backend);
    expect(find.text(r' \_o.o_/  '), findsOneWidget);
    await _openSheet(tester);
    expect(find.text('Your egg is ready'), findsOneWidget);
    await tester.tap(find.text('Hatch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('daemon-hatch-egg')), findsOneWidget);
    // The chip keeps the egg while the reveal runs.
    expect(app.zoo.paired!.id, 'tim');

    var sawSilhouette = false, sawBanner = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final sprite = find.byKey(const ValueKey('daemon-hatch-sprite'));
      if (sprite.evaluate().isNotEmpty &&
          RegExp(r'^[# ]+$').hasMatch(tester.widget<Text>(sprite).data!)) {
        sawSilhouette = true;
      }
      if (find
          .byKey(const ValueKey('daemon-hatch-banner'))
          .evaluate()
          .isNotEmpty) {
        sawBanner = true;
      }
      if (find
          .byKey(const ValueKey('daemon-hatch-card'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(sawSilhouette, isTrue);
    expect(sawBanner, isTrue);
    expect(platform.haptics, contains('HapticFeedbackType.mediumImpact'));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon-hatch-stamp')))
          .data,
      '[ * SHINY * COMMON ]  #01/09',
    );
    expect(
      find.textContaining("fork() returned 0. it's a tim."),
      findsOneWidget,
    );
    final card = tester
        .widget<DaemonCardView>(find.byKey(const ValueKey('daemon-hatch-card')))
        .text;
    expect(card, contains('tim 0.1'));
    expect(card, contains('first egg'));

    await tester.tap(find.byKey(const ValueKey('daemon-hatch-share')));
    await tester.pump();
    expect(platform.clipboard, '```\n$card\n```');
    expect(
      find.text('Copied as a code block. Paste it anywhere.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('daemon-hatch-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daemon-hatch')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    final chipText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('daemon-chip')),
            matching: find.byType(Text),
          )
          .last,
    );
    expect(chipText.data, r'  [o o]   ');
    // This one hatched shiny: its star before the slot.
    expect(find.byKey(const ValueKey('daemon-chip-shiny')), findsOneWidget);
  });

  testWidgets('a secret starts pitch black', (tester) async {
    backend.zoo = _nest(egg: true);
    backend.nextDaemon = 'grue';
    await _pump(tester, backend);
    await _openSheet(tester);
    await tester.tap(find.text('Hatch'));
    var pitch = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const ValueKey('daemon-hatch-pitch'))
          .evaluate()
          .isNotEmpty) {
        pitch = true;
        // Nothing of it is shown yet: only the dark.
        expect(find.byKey(const ValueKey('daemon-hatch-sprite')), findsNothing);
        final scaffold = tester.widget<Scaffold>(
          find.byKey(const ValueKey('daemon-hatch')),
        );
        expect(scaffold.backgroundColor, const Color(0xFF000000));
        break;
      }
    }
    expect(pitch, isTrue);
    await _toCard(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon-hatch-stamp')))
          .data,
      startsWith('[ * SHINY * SECRET ]  #S/09'),
    );
  });

  testWidgets('Reduce Motion goes straight to the card', (tester) async {
    backend.zoo = _nest(egg: true);
    await _pump(tester, backend, reduceMotion: true);
    await _openSheet(tester);
    await tester.tap(find.text('Hatch'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('daemon-hatch-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('daemon-hatch-banner')), findsOneWidget);
  });

  testWidgets('an egg the zoo cannot open stays in the nest', (tester) async {
    backend.zoo = _nest(egg: true);
    final app = await _pump(tester, backend, reduceMotion: true);
    backend.failWrites = true;
    await _openSheet(tester);
    await tester.tap(find.text('Hatch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('daemon-hatch-failed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daemon-hatch-done')));
    await tester.pumpAndSettle();
    expect(app.zoo.readyEgg, isNotNull);
  });

  for (final (name, size, scale) in [
    ('a 320pt phone', const Size(320, 568), 1.0),
    ('large text', const Size(390, 844), 2.0),
    ('large text on a 320pt phone', const Size(320, 568), 1.6),
  ]) {
    testWidgets('nothing overflows on $name', (tester) async {
      backend.zoo = {
        ...backend.zoo,
        'daemons': [
          for (final id in ['tim', 'vim', 'fzf', 'grue', 'zsh'])
            {'id': id, 'hatchedAt': '2026-09-26T09:42:00Z', 'egg': 'turn'},
        ],
        'pair': 'fzf',
      };
      backend.nextDaemon = 'tldr';
      await _pump(tester, backend, size: size, textScale: scale);
      await _openSheet(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('daemon-sheet')),
        const Offset(0, -2000),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('daemon-sheet')),
        const Offset(0, 2000),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Hatch'),
        120,
        scrollable: _sheetScroll,
      );
      await tester.ensureVisible(find.text('Hatch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hatch').first);
      await _toCard(tester);
      expect(tester.takeException(), isNull);
      // The card keeps its columns: scaled to fit, never wrapped.
      final card = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('daemon-hatch-card')),
          matching: find.byType(Text),
        ),
      );
      expect(card.softWrap, isFalse);
      expect(
        tester.getRect(find.byKey(const ValueKey('daemon-hatch-card'))).width,
        lessThanOrEqualTo(size.width),
      );
    });
  }

  testWidgets('the name is a banner that fits a 320pt screen, never wrapped', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final app = pagerApp(PagerConn());
    addTearDown(app.dispose);
    final banner = find.byKey(const ValueKey('daemon-hatch-banner'));
    final box = find.ancestor(of: banner, matching: find.byType(FittedBox));

    Future<void> still(String id, int rows, {double textScale = 1}) async {
      final def = daemonRoster.byId(id)!;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: DaemonHatchReveal(
            // A still is read once: a new one for every frame.
            key: ValueKey('$id $rows $textScale'),
            roster: daemonRoster,
            egg: const ZooEgg(id: 'e', kind: 'first', grantedAt: ''),
            result: Future.value(
              ZooHatch(eggId: 'e', daemonId: id, shiny: false),
            ),
            zoo: app.zoo,
            still: HatchFrame(
              stage: HatchStage.banner,
              sprite: renderSprite(daemonRoster, def, 0, DaemonMood.idle),
              bannerRows: rows,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: id);
    }

    for (final d in daemonRoster.daemons) {
      final rows = renderBanner(daemonBanner, d.id);
      await still(d.id, rows.length);
      final text = tester.widget<Text>(banner);
      expect(text.data, rows.join('\n'), reason: d.id);
      expect(text.softWrap, isFalse);
      expect(text.textScaler, TextScaler.noScaling);
      expect(text.style!.height, 1.15);
      expect(text.style!.fontSize, 18);
      // One line per row: nothing wrapped, whatever the scale it is drawn at.
      final unwrapped = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(unwrapped.dispose);
      expect(unwrapped.computeLineMetrics(), hasLength(rows.length));
      expect(tester.getSize(banner), unwrapped.size, reason: d.id);
      // Inside the reveal's 20pt margins: scaled down when it must be.
      final drawn = tester.getRect(box);
      expect(drawn.left, greaterThanOrEqualTo(20 - .01), reason: d.id);
      expect(drawn.right, lessThanOrEqualTo(300 + .01), reason: d.id);
      expect(tester.getSemantics(box).label, d.id);
    }

    // Typing in a row at a time never moves or rescales what is there.
    final rows = renderBanner(daemonBanner, 'grue');
    await still('grue', 1);
    final first = tester.getRect(box);
    expect(tester.widget<Text>(banner).data, rows.first);
    await still('grue', rows.length);
    expect(tester.getRect(box), first);

    // Larger text does not grow art that would only be scaled back down (the
    // words around it grow, and move it).
    await still('grue', rows.length, textScale: 2);
    expect(tester.getRect(box).size, first.size);
  });

  testWidgets('a still of the reveal draws any moment', (tester) async {
    final app = pagerApp(PagerConn());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DaemonHatchReveal(
          roster: daemonRoster,
          egg: const ZooEgg(id: 'e', kind: 'night', grantedAt: ''),
          result: Future.value(
            const ZooHatch(eggId: 'e', daemonId: 'bat', shiny: false),
          ),
          zoo: app.zoo,
          still: const HatchFrame(
            stage: HatchStage.silhouette,
            sprite: '#####',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('#####'), findsOneWidget);
  });

  // ── economy v2 ─────────────────────────────────────────────────────────────

  Map<String, dynamic> daemon(
    String id, {
    int xp = 0,
    bool shiny = false,
    int? serial,
    int? dupes,
    String? origin,
  }) => {
    'id': id,
    'hatchedAt': '2026-09-26T12:00:00Z',
    'egg': 'first',
    'xp': xp,
    'shiny': shiny,
    'serial': ?serial,
    'dupes': ?dupes,
    'origin': ?origin,
  };

  Text chipText(WidgetTester tester) => tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(const ValueKey('daemon-chip')),
          matching: find.byType(Text),
        )
        .last,
  );

  testWidgets('a shiny daemon wears its shiny colour, and a * on the chip', (
    tester,
  ) async {
    backend.zoo = {
      'daemons': [daemon('tim', shiny: true)],
      'pair': 'tim',
      'firstEgg': true,
    };
    await _pump(tester, backend);
    final tim = daemonRoster.byId('tim')!;
    // The star stands before the slot, which stays ten cells.
    final star = find.byKey(const ValueKey('daemon-chip-shiny'));
    expect(tester.widget<Text>(star).data, '*');
    expect(tester.widget<Text>(star).style!.color, tim.colorFor(shiny: true));
    expect(chipText(tester).data, r'  [o o]   ');
    expect(chipText(tester).style!.color, tim.colorFor(shiny: true));
    expect(tim.colorFor(shiny: true), const Color(0xFF00FFAF));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('daemon-chip'))).label,
      'tim, tim 0.1, shiny, content',
    );
    await _openSheet(tester);
    await tester.pump(const Duration(seconds: 1));
    final portrait = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('daemon-portrait')),
        matching: find.byType(Text),
      ),
    );
    expect(portrait.style!.color, tim.colorFor(shiny: true));
    expect(find.text('SHINY COMMON  #01/09'), findsOneWidget);
  });

  testWidgets('the sheet shows the serial, its card copies, a guest has none', (
    tester,
  ) async {
    final platform = _Platform()..install(tester);
    backend.zoo = {
      'daemons': [
        daemon('tim', xp: 600, serial: 42, shiny: true),
        daemon('vim', serial: 9, origin: 'local'),
      ],
      'pair': 'tim',
      'firstEgg': true,
      'setupEgg': true,
    };
    final app = await _pump(tester, backend);
    await _openSheet(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('daemon-version'))).data,
      '2.0  #0042',
    );
    final card = find.byKey(const ValueKey('daemon-card'));
    await tester.scrollUntilVisible(card, 200, scrollable: _sheetScroll);
    final view = tester.widget<DaemonCardView>(card);
    expect(view.text, contains('tim 2.0  #0042'));
    expect(view.text, contains('SHINY COMMON'));
    expect(view.shiny, isTrue);
    expect(
      tester.getSemantics(card).label,
      'The card: tim, shiny common, #0042',
    );
    // The portrait rows wear the shiny colour; the words stay ink.
    final rich = tester
        .widget<Text>(find.descendant(of: card, matching: find.byType(Text)))
        .textSpan!;
    final rows = (rich as TextSpan).children!.cast<TextSpan>();
    final tim = daemonRoster.byId('tim')!;
    final portrait = cardPortraitRows(daemonRoster, tim, '2.0');
    expect(rows[portrait.from].style!.color, tim.colorFor(shiny: true));
    expect(rows[portrait.to].style, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('daemon-card-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daemon-card-share')));
    await tester.pump();
    expect(platform.clipboard, fencedCard(view.lines));
    expect(find.text('Copied as a code block.'), findsOneWidget);

    // A guest's daemon, seeded: no serial on its sheet or its card.
    app.zoo.pair('vim');
    await tester.pump();
    expect(
      tester.widget<DaemonCardView>(card).text,
      isNot(contains(RegExp(r'#\d{4}'))),
    );
    expect(tester.widget<DaemonCardView>(card).serial, isNull);
    await tester.drag(
      find.byKey(const ValueKey('daemon-sheet')),
      const Offset(0, 3000),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('daemon-version'))).data,
      '0.1',
    );
    await app.zoo.settle();
  });

  testWidgets('the shelf counts duplicates, marks shiny ones and the pair', (
    tester,
  ) async {
    backend.zoo = {
      'daemons': [daemon('tim', dupes: 1, shiny: true), daemon('vim')],
      'pair': 'tim',
      'firstEgg': true,
      'setupEgg': true,
    };
    await _pump(tester, backend);
    await _openSheet(tester);
    final tim = find.byKey(const ValueKey('daemon-shelf-tim'));
    await tester.scrollUntilVisible(tim, 200, scrollable: _sheetScroll);
    expect(tester.getSemantics(tim).label, 'tim, shiny, 2 of it, paired');
    expect(find.text('> tim* x2'), findsOneWidget);
    expect(find.text('vim'), findsOneWidget);
    final sprite = tester.widget<Text>(
      find.descendant(of: tim, matching: find.byType(Text)).first,
    );
    expect(
      sprite.style!.color,
      daemonRoster.byId('tim')!.colorFor(shiny: true),
    );
    // One shelf: drop 1 is the only drop, and it is out.
    expect(find.textContaining('zoo: drop 1 unix  2/9'), findsOneWidget);
  });

  testWidgets('a drop announced but not released shows as silhouettes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
    final roster = rosterWithDropTwo();
    backend.zoo = {
      'daemons': [daemon('tim')],
      'pair': 'tim',
      'firstEgg': true,
      'setupEgg': true,
    };
    Future<void> sheetOn(DateTime day) async {
      final zoo = ZooClient(
        read: backend.read,
        write: backend.write,
        roster: roster,
      );
      final face = DaemonFace(zoo, now: () => day);
      addTearDown(() {
        face.dispose();
        zoo.dispose();
      });
      zoo.ensure();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            key: ValueKey(day),
            backgroundColor: DaemonInk.ground,
            body: DaemonSheet(
              face: face,
              facts: () => const DaemonFacts(),
              onHatch: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Not announced yet: shown nowhere.
    await sheetOn(DateTime.utc(2026, 9, 30));
    expect(
      find.byKey(const ValueKey('daemon-shelf-drop-unix')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('daemon-shelf-drop-bsd')), findsNothing);

    // Announced: its regulars as `#` silhouettes, its name and release date.
    await sheetOn(DateTime.utc(2026, 10, 5));
    final bsd = find.byKey(const ValueKey('daemon-shelf-drop-bsd'));
    await tester.scrollUntilVisible(bsd, 200, scrollable: _sheetScroll);
    expect(
      find.descendant(
        of: bsd,
        matching: find.text('zoo: drop 2 bsd  out 2026-10-15'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bsd, matching: find.text('## ##')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daemon-shelf-bsd-#01')))
          .label,
      'Number 01 of drop 2 bsd, out 2026-10-15',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daemon-shelf-bsd-secret')))
          .label,
      'A secret of drop 2 bsd, out 2026-10-15',
    );

    // Released: empty slots like any other drop.
    await sheetOn(DateTime.utc(2026, 10, 15));
    await tester.scrollUntilVisible(bsd, 200, scrollable: _sheetScroll);
    expect(
      find.descendant(of: bsd, matching: find.text('zoo: drop 2 bsd  0/3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bsd, matching: find.text('## ##')),
      findsNothing,
    );
  });

  testWidgets('habits: the copy comes from the rules, then the setup egg', (
    tester,
  ) async {
    final rules = daemonRoster.rules;
    final required = rules.habits
        .firstWhere((h) => rules.firstEggRequire.contains(h.key))
        .label;
    backend.zoo = _nest(habits: const ['turn', 'split']);
    await _pump(tester, backend);
    await _openSheet(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon-habits-intro')))
          .data,
      'The first egg arrives after any ${rules.firstEggNeed} of these, the '
      'required one included. The setup egg follows at '
      '${rules.setupEggNeed}. 2 done.',
    );
    expect(find.bySemanticsLabel('$required, required, done'), findsOneWidget);
    expect(find.text('Hatch'), findsNothing);
  });

  testWidgets('the setup egg sits in the nest like any other egg', (
    tester,
  ) async {
    final rules = daemonRoster.rules;
    backend.zoo = {
      'daemons': [daemon('tim')],
      'eggs': [
        {'id': 's', 'kind': 'setup', 'grantedAt': ''},
      ],
      'pair': 'tim',
      'habits': ['turn', 'split', 'find', 'machine'],
      'firstEgg': true,
    };
    await _pump(tester, backend);
    await _openSheet(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(rules.eggs['setup']!.look), findsOneWidget);
    expect(find.text(r'\_$_/'), findsOneWidget);
    expect(find.text('setup egg'), findsOneWidget);
    expect(find.byKey(const ValueKey('daemon-hatch-setup')), findsOneWidget);
    // The setup egg has not been granted yet: the habits say when it comes.
    final intro = find.byKey(const ValueKey('daemon-habits-intro'));
    await tester.scrollUntilVisible(intro, 200, scrollable: _sheetScroll);
    expect(
      tester.widget<Text>(intro).data,
      'The setup egg arrives after any ${rules.setupEggNeed} of these. '
      '4 done.',
    );
  });

  testWidgets('with both habit eggs granted, the habits are gone', (
    tester,
  ) async {
    backend.zoo = {
      'daemons': [daemon('tim')],
      'pair': 'tim',
      'habits': ['turn', 'split', 'find', 'machine', 'store', 'days'],
      'firstEgg': true,
      'setupEgg': true,
    };
    await _pump(tester, backend);
    await _openSheet(tester);
    await tester.drag(
      find.byKey(const ValueKey('daemon-sheet')),
      const Offset(0, -3000),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('daemon-habits-intro')), findsNothing);
    expect(find.text('HABITS'), findsNothing);
  });

  testWidgets('a duplicate says what it merged into, then the level', (
    tester,
  ) async {
    backend.zoo = {
      'daemons': [daemon('tim')],
      'eggs': [
        {'id': 'e1', 'kind': 'turn', 'grantedAt': ''},
      ],
      'pair': 'tim',
      'firstEgg': true,
      'setupEgg': true,
    };
    backend.nextDaemon = 'tim';
    final app = await _pump(tester, backend);
    await _openSheet(tester);
    await tester.tap(find.text('Hatch'));
    var sawBanner = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const ValueKey('daemon-hatch-banner'))
          .evaluate()
          .isNotEmpty) {
        sawBanner = true;
      }
      if (find
          .byKey(const ValueKey('daemon-hatch-merged'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    // No name to reveal, and no new daemon's card.
    expect(sawBanner, isFalse);
    expect(find.byKey(const ValueKey('daemon-hatch-card')), findsNothing);
    expect(find.byKey(const ValueKey('daemon-hatch-share')), findsNothing);
    expect(find.text('fork() returned 0. another tim.'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon-hatch-merged')))
          .data,
      'tim x2 · +${daemonRoster.rules.duplicateXp} xp · now shiny',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('daemon-hatch-level')))
          .data,
      'level up · bond 2/4 · now tim 1.0',
    );
    await tester.tap(find.byKey(const ValueKey('daemon-hatch-done')));
    await tester.pumpAndSettle();
    expect(app.zoo.zoo.daemon('tim')!.dupes, 1);
    // The chip: the same daemon, grown and now shiny.
    await tester.pump(const Duration(seconds: 2));
    expect(chipText(tester).data, r'  [o|o]   ');
    expect(find.byKey(const ValueKey('daemon-chip-shiny')), findsOneWidget);
  });

  testWidgets('a new daemon\'s card carries its serial', (tester) async {
    backend.zoo = _nest(egg: true);
    backend.nextDaemon = 'tim';
    backend.nextSerial = 42;
    backend.nextShiny = false;
    await _pump(tester, backend, reduceMotion: true);
    await _openSheet(tester);
    await tester.tap(find.text('Hatch'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final card = tester.widget<DaemonCardView>(
      find.byKey(const ValueKey('daemon-hatch-card')),
    );
    expect(card.text, contains('tim 0.1  #0042'));
    expect(card.shiny, isFalse);
    expect(card.serial, 42);
  });

  testWidgets('an egg that became xp shows as +xp, not as an egg', (
    tester,
  ) async {
    backend.grants = [
      {'kind': 'turn', 'xp': 50},
    ];
    final app = await _pump(tester, backend);
    final eggs = app.zoo.zoo.eggs.length;
    app.zoo.habit('find');
    await app.zoo.settle();
    await tester.pump();
    expect(app.zoo.zoo.eggs, hasLength(eggs));
    await _openSheet(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('+50 xp · a turn egg, with no room to hold it'),
      findsOneWidget,
    );
    // Seen once: closing the sheet forgets it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(app.zoo.xpGrants, isEmpty);
  });
}
