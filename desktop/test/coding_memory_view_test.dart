import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/companions/coding_memory_library.dart';
import 'package:harness/companions/coding_memory_view.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/theme/color_palette.dart';

import 'support/coding_memory_fixture.dart';
import 'support/real_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadRealFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide400')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w400.ttf',
          ),
        ))
        .load();
  });
  late MemoryFixture transport;
  late CodingMemoryLibrary library;
  late GlobalKey boundary;
  setUp(() {
    transport = MemoryFixture();
    library = CodingMemoryLibrary(transport);
    boundary = GlobalKey();
  });
  tearDown(() => library.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
    Size size = const Size(850, 850),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final oldPalette = AppTheme.palette.value,
        oldBrightness = AppTheme.brightness.value;
    AppTheme.palette.value = brightness == Brightness.dark
        ? HarnessPalette.graphite
        : HarnessPalette.paper;
    AppTheme.brightness.value = brightness;
    addTearDown(() {
      AppTheme.palette.value = oldPalette;
      AppTheme.brightness.value = oldBrightness;
    });
    await library.refresh();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: CodingMemoryView(library: library),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final button = find.text(label).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'detail exposes retained evidence; forgetting requires a concrete preview and defaults to cancel',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      expect(
        find.text('When fixing a bug, write a small failing test first.'),
        findsOneWidget,
      );
      await tap(tester, 'Forget…');
      expect(find.textContaining('removes 2 memories'), findsOneWidget);
      expect(
        find.textContaining('Original conversations and context already sent'),
        findsOneWidget,
      );
      expect(transport.calls.where((c) => c['action'] == 'apply'), isEmpty);
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancel.focusNode!.hasFocus, isTrue);
      await tap(tester, 'Cancel');
      expect(transport.present, isTrue);
      await tap(tester, 'Read memory');
      await tap(tester, 'Forget…');
      await tap(tester, 'Forget memory');
      expect(transport.present, isFalse);
      expect(find.text('Read memory'), findsNothing);
    },
  );

  testWidgets(
    'stale correction preserves the draft and shows the current version before retry',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Correct memory');
      await tester.enterText(
        find.byType(TextFormField).first,
        'Prefer one focused regression test per bug.',
      );
      await tap(tester, 'Review correction');
      transport.refuseApply = 'PREVIEW_CHANGED';
      await tap(tester, 'Save correction');
      expect(
        find.text('Prefer one focused regression test per bug.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your edit is still here'), findsOneWidget);
      transport.record = syntheticMemory(
        revision: 2,
        claim: 'Use integration tests at service boundaries.',
      );
      transport.refuseApply = null;
      await tap(tester, 'Refresh current version');
      expect(
        find.text('Use integration tests at service boundaries.'),
        findsOneWidget,
      );
      expect(
        find.text('Prefer one focused regression test per bug.'),
        findsOneWidget,
      );
      await tap(tester, 'Review correction');
      expect(transport.previewed!['revision'], 2);
      expect((transport.previewed!['fields'] as Map)['applicability'], {
        'task': 'bug_fix',
      });
      await tap(tester, 'Save correction');
      expect(
        transport.record['claim'],
        'Prefer one focused regression test per bug.',
      );
    },
  );

  testWidgets('account change clears open evidence and disables saving', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'Read memory');
    transport.invalidate();
    await tester.pumpAndSettle();
    expect(
      find.text('When fixing a bug, write a small failing test first.'),
      findsNothing,
    );
    expect(find.text('Correct memory'), findsNothing);
    expect(find.text('Memory unavailable'), findsOneWidget);
  });

  testWidgets(
    'refresh removes forgotten evidence from an already open detail view',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      transport.present = false;
      transport.record = syntheticMemory(revision: 2);
      await library.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('When fixing a bug, write a small failing test first.'),
        findsNothing,
      );
      expect(find.text('Correct memory'), findsNothing);
      expect(
        find.textContaining('removed or is no longer available'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'privacy refresh during editing preserves the draft without keeping source evidence',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Correct memory');
      await tester.enterText(
        find.byType(TextFormField).first,
        'My unsaved correction.',
      );
      transport.record = syntheticMemory(
        revision: 2,
        claim: 'A changed preference.',
      );
      await library.refresh();
      await tester.pumpAndSettle();
      expect(find.text('My unsaved correction.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('A changed preference.'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('When fixing a bug, write a small failing test first.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'learning and recall remain independent and do not change until settings are applied',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Learning');
      expect(find.textContaining('4 session segments'), findsOneWidget);
      expect(find.textContaining('1 segment expired'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(transport.learn, isTrue);
      expect(find.text('Learning: Paused'), findsOneWidget);
      expect(find.text('Recall: On'), findsOneWidget);
      await tap(tester, 'Apply settings');
      expect(transport.learn, isFalse);
      expect(transport.recall, isTrue);
    },
  );

  testWidgets('a pending apply disables close and cannot submit twice', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'Read memory');
    await tap(tester, 'Forget…');
    final pending = Completer<Map<String, dynamic>>();
    transport.handle = (p) async =>
        p['action'] == 'apply' ? pending.future : transport.respond(p);
    await tester.tap(find.text('Forget memory'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .onPressed,
      isNull,
    );
    expect(find.text('Forget memory'), findsNothing);
    pending.complete({'ok': true});
    await tester.pumpAndSettle();
    expect(transport.calls.where((c) => c['action'] == 'apply'), hasLength(1));
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'memory review fits ${brightness.name} at ${scale}x and narrow width',
        (tester) async {
          await mount(
            tester,
            brightness: brightness,
            scale: scale,
            size: Size(scale == 1 ? 760 : 480, 820),
          );
          await tap(tester, 'Read memory');
          expect(tester.takeException(), isNull);
          final output = Platform.environment['HARNESS_MEMORY_CAPTURE_DIR'];
          if (output != null) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File('$output/memory-${brightness.name}-${scale}x.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tap(tester, 'Correct memory');
          expect(tester.takeException(), isNull);
          await tap(tester, 'Review correction');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
