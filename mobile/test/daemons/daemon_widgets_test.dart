// The daemon where a phone meets it: the chip in the header, its sheet, and
// the full-screen hatch reveal — on a 320pt phone and with large text too.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';
import 'package:harness_mobile/phone/daemon_chip.dart';
import 'package:harness_mobile/phone/daemon_hatch.dart';
import 'package:harness_mobile/phone/daemon_scope.dart';
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
    // The line is the truth: nothing is waiting on this phone.
    expect(find.byKey(const ValueKey('daemon-line')), findsOneWidget);
    expect(find.textContaining('idle. nothing needs you.'), findsOneWidget);
    expect(find.textContaining('screen -> tmux -> tim'), findsOneWidget);
    expect(find.textContaining('zoo: drop 1 unix  2/9'), findsOneWidget);
    expect(find.text('Hatch'), findsOneWidget);
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
    expect(find.text('vim'), findsWidgets);
    // Empty slots are numbered; the secret is a `[ ! ]`.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('daemon-shelf-#03'))).label,
      'Number 03, not hatched yet',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daemon-shelf-secret')))
          .label,
      'A secret, not found yet',
    );
  });

  testWidgets('before any daemon the sheet is the nest and its habits', (
    tester,
  ) async {
    backend.zoo = _nest(habits: const ['turn', 'split', 'find']);
    await _pump(tester, backend);
    expect(find.text(r' ~\_O_/~  '), findsOneWidget);
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
        .widget<Text>(find.byKey(const ValueKey('daemon-hatch-card')))
        .data!;
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
      find.descendant(
        of: find.byKey(const ValueKey('daemon-chip')),
        matching: find.byType(Text),
      ),
    );
    expect(chipText.data, r'  [o o]   ');
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
      await tester.ensureVisible(find.text('Hatch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hatch').first);
      await _toCard(tester);
      expect(tester.takeException(), isNull);
      // The card keeps its columns: scaled to fit, never wrapped.
      final card = tester.widget<Text>(
        find.byKey(const ValueKey('daemon-hatch-card')),
      );
      expect(card.softWrap, isFalse);
      expect(
        tester.getRect(find.byKey(const ValueKey('daemon-hatch-card'))).width,
        lessThanOrEqualTo(size.width),
      );
    });
  }

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
}
