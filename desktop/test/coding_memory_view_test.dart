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

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['HARNESS_MEMORY_CAPTURE_DIR'];
    if (output == null) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
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
    'project search is read-only; narrowing previews the selected folder and preserves evidence',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Limit to a project…');
      expect(find.text('/synthetic/work/editor'), findsOneWidget);
      expect(find.text('/synthetic/research/editor'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'research');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('/synthetic/work/editor'), findsNothing);
      expect(
        transport.calls.where(
          (c) => ['preview', 'apply'].contains(c['action']),
        ),
        isEmpty,
      );
      await tap(tester, '/synthetic/research/editor');
      expect(transport.previewed, {
        'kind': 'narrow',
        'id': 'synthetic-memory',
        'revision': 1,
        'projectId': 'second-project',
      });
      expect(find.text('Limit this memory to a project?'), findsOneWidget);
      expect(
        find.textContaining('Limiting a memory does not confirm it'),
        findsOneWidget,
      );
      expect((transport.record['scope'] as Map)['projectId'], isNull);
      await tap(tester, 'Back');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'research',
      );
      await tap(tester, '/synthetic/research/editor');
      final before = syntheticMemory();
      final pending = Completer<Map<String, dynamic>>();
      transport.handle = (p) async =>
          p['action'] == 'apply' ? pending.future : transport.respond(p);
      await tester.tap(find.text('Limit to project'));
      await tester.pump();
      expect(find.text('Limit to project'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull,
      );
      pending.complete(transport.respond({'action': 'apply'}));
      await tester.pumpAndSettle();
      expect(
        transport.calls.where((c) => c['action'] == 'apply'),
        hasLength(1),
      );
      for (final key in [
        'claim',
        'evidence',
        'evidenceClass',
        'state',
        'applicability',
        'exceptions',
      ]) {
        expect(transport.record[key], before[key]);
      }
      await tap(tester, 'Read memory');
      expect(find.text('/synthetic/research/editor'), findsOneWidget);
      expect(find.textContaining('Its evidence is unchanged'), findsOneWidget);
      expect(find.text('Limit to a project…'), findsNothing);
    },
  );

  testWidgets(
    'a changed revision must be reviewed before another project preview',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Limit to a project…');
      transport.record = syntheticMemory(
        revision: 2,
        claim: 'A newer preference to review.',
      );
      await library.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Choose a project'), findsNothing);
      expect(find.textContaining('Review its current details'), findsOneWidget);
      expect(transport.calls.where((c) => c['action'] == 'preview'), isEmpty);
      await tap(tester, 'Limit to a project…');
      await tap(tester, '/synthetic/work/editor');
      expect(transport.previewed!['revision'], 2);
      await tap(tester, 'Cancel');
      expect(transport.calls.where((c) => c['action'] == 'apply'), isEmpty);
    },
  );

  testWidgets(
    'late project searches and account changes cannot restore old choices',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      final older = Completer<Map<String, dynamic>>(),
          newer = Completer<Map<String, dynamic>>();
      transport.handle = (p) async {
        if (p['action'] != 'projects') return transport.respond(p);
        return (p['query'] as Map)['search'] == ''
            ? older.future
            : newer.future;
      };
      await tester.ensureVisible(find.text('Limit to a project…'));
      await tester.tap(find.text('Limit to a project…'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'research');
      await tester.pump(const Duration(milliseconds: 250));
      newer.complete({
        'ok': true,
        'items': [transport.projects.last],
        'nextBefore': null,
      });
      await tester.pumpAndSettle();
      expect(find.text('/synthetic/research/editor'), findsOneWidget);
      older.complete({
        'ok': true,
        'items': [transport.projects.first],
        'nextBefore': null,
      });
      await tester.pumpAndSettle();
      expect(find.text('/synthetic/work/editor'), findsNothing);
      final late = Completer<Map<String, dynamic>>();
      transport.handle = (p) async => late.future;
      await tester.enterText(find.byType(TextField), 'work');
      await tester.pump(const Duration(milliseconds: 250));
      transport.invalidate();
      await tester.pumpAndSettle();
      late.complete({
        'ok': true,
        'items': transport.projects,
        'nextBefore': null,
      });
      await tester.pumpAndSettle();
      expect(find.text('Memory unavailable'), findsOneWidget);
      expect(find.text('/synthetic/work/editor'), findsNothing);
      expect(find.text('/synthetic/research/editor'), findsNothing);
      expect(
        transport.calls.where(
          (c) => ['preview', 'apply'].contains(c['action']),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'privacy refresh removes excluded project rows from an open picker',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Limit to a project…');
      transport.projects.removeLast();
      transport.learn = false; // A changed library policy snapshot.
      await library.refresh();
      await tester.pumpAndSettle();
      expect(find.text('/synthetic/research/editor'), findsNothing);
      expect(find.text('/synthetic/work/editor'), findsOneWidget);
      expect(
        transport.calls.where(
          (c) => ['preview', 'apply'].contains(c['action']),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'an unavailable destination refreshes choices without substituting another project',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      await tap(tester, 'Limit to a project…');
      transport.handle = (p) async {
        if (p['action'] == 'preview') {
          transport.projects.removeLast();
          return {'ok': false, 'error': 'PROJECT_UNAVAILABLE'};
        }
        return transport.respond(p);
      };
      await tap(tester, '/synthetic/research/editor');
      expect(find.textContaining('Choose another project'), findsOneWidget);
      expect(find.text('/synthetic/research/editor'), findsNothing);
      expect(find.text('/synthetic/work/editor'), findsOneWidget);
      expect(
        transport.calls.where((c) => c['action'] == 'preview'),
        hasLength(1),
      );
      expect(transport.calls.where((c) => c['action'] == 'apply'), isEmpty);
    },
  );

  testWidgets(
    'search Return and paging only browse; Escape backs out one level',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Read memory');
      transport.handle = (p) async {
        if (p['action'] == 'projects') {
          final query = p['query'] as Map;
          return {
            'ok': true,
            'items': [
              query['before'] == null
                  ? transport.projects.first
                  : transport.projects.last,
            ],
            'nextBefore': query['before'] == null ? 9 : null,
          };
        }
        return transport.respond(p);
      };
      await tap(tester, 'Limit to a project…');
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(transport.calls.where((c) => c['action'] == 'preview'), isEmpty);
      await tap(tester, 'More projects');
      expect((transport.calls.last['query'] as Map)['before'], 9);
      await tap(tester, '/synthetic/research/editor');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Choose a project'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Your coding memory'), findsNWidgets(2));
      expect(find.text('Choose a project'), findsNothing);
      expect(transport.calls.where((c) => c['action'] == 'apply'), isEmpty);
    },
  );

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
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
        'project choices and preview fit ${brightness.name} at ${scale}x in a short window',
        (tester) async {
          const name = 'editor-with-a-very-long-but-recognizable-project-name';
          const location =
              '/synthetic/development/a-very-long-path-that-distinguishes-this-checkout/editor';
          transport.projects.first.addAll({'name': name, 'location': location});
          await mount(
            tester,
            brightness: brightness,
            scale: scale,
            size: Size(scale == 1 ? 760 : 480, 620),
          );
          await tap(tester, 'Read memory');
          await tap(tester, 'Limit to a project…');
          expect(tester.takeException(), isNull);
          await capture(tester, 'project-picker-${brightness.name}-${scale}x');
          await tap(tester, name);
          expect(tester.takeException(), isNull);
          await capture(tester, 'scope-preview-${brightness.name}-${scale}x');
          await tap(tester, 'Cancel');
          expect(transport.calls.where((c) => c['action'] == 'apply'), isEmpty);
        },
      );
    }
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
          await capture(tester, 'memory-${brightness.name}-${scale}x');
          await tap(tester, 'Correct memory');
          expect(tester.takeException(), isNull);
          await tap(tester, 'Review correction');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
