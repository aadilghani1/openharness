import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/theme/color_palette.dart';
import 'package:harness/terminal/terminal_text.dart';
import 'package:harness/terminal/terminal_theme_store.dart';
import 'package:harness/widgets/session_work_dialog.dart';
import 'package:xterm/xterm.dart' show TerminalStyle;

import 'session_git_context_test.dart';
import 'support/real_fonts.dart';

Future<void> captureDialog(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final output = Platform.environment['HARNESS_GIT_CONTEXT_CAPTURE_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await render.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  final capture = Platform.environment['HARNESS_GIT_CONTEXT_CAPTURE_DIR'];
  setUpAll(() async {
    await loadRealFonts();
    // Optional local captures use the actual macOS terminal face. Portable
    // regression runs retain the shared metric-compatible test fonts.
    if (capture != null && Platform.isMacOS) {
      final bytes = await File('/System/Library/Fonts/SFNSMono.ttf')
          .readAsBytes();
      await (FontLoader(
        'WorkDialogPreviewMono',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() {
    final old = terminalFontStore.value;
    if (capture != null && Platform.isMacOS) {
      terminalFontStore.value = const TerminalStyle(
        fontFamily: 'WorkDialogPreviewMono',
        fontSize: 18,
      );
    }
    addTearDown(() => terminalFontStore.value = old);
  });
  testWidgets(
    'opening work details preserves launch context and only follows the selected PR link',
    (tester) async {
      final opened = <Uri>[];
      final git = gitFixture();
      git['activityUncertain'] = true;
      git['checkouts'] = [git['current']];
      git['recentWork'] = {
        'project': git['current'],
        'at': '2026-09-27T13:00:00Z',
      };
      git['history']['pullRequests'][0]['result'].addAll({
        'headBranch': 'hn/preview-fix',
        'baseBranch': 'main',
        'headRepository': 'acme/app',
        'title': 'Keep complete session previews',
      });
      git['history']['branches'].add({
        'cwd': '/removed-temporary-checkout',
        'remote': 'github.com/acme/app',
        'branch': 'hn/nfc',
        'at': '2026-09-26T13:00:00Z',
      });
      git['history']['pullRequests'].add({
        'url': 'https://github.com/acme/app/pull/119',
        'cwd': '/removed-temporary-checkout',
        'at': '2026-09-26T13:00:00Z',
        'checkedAt': '2026-09-27T13:01:00Z',
        'result': {
          'status': 'found',
          'url': 'https://github.com/acme/app/pull/119',
          'number': 119,
          'state': 'Merged',
          'headBranch': 'hn/nfc',
          'baseBranch': 'main',
          'headRepository': 'acme/app',
          'title': 'Keep NFC conversations in order',
        },
      });
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: Scaffold(
              body: SessionWorkDialog(
                agent: workAgent(git: git),
                read: (_) async => {
                  'gitContext': git,
                  'history': git['history'],
                },
                open: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('/silent-beacon'), findsNothing);
      expect(find.textContaining('/ship-hn'), findsNothing);
      expect(find.text('hn/preview-fix'), findsOneWidget);
      expect(find.text('Recent work'), findsOneWidget);
      expect(find.text('acme/app · 2 branches · 2 PRs'), findsOneWidget);
      expect(find.text('#12'), findsOneWidget);
      expect(find.text('Keep complete session previews'), findsOneWidget);
      expect(find.text('#119'), findsNothing);
      expect(find.text('[ Completed (1) ]'), findsOneWidget);
      expect(find.textContaining('Checked 2026'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('work-dialog-surface')))
            .height,
        lessThan(360),
      );
      expect(find.text('Work location unknown'), findsNothing);

      await captureDialog(tester, boundary, 'work-last-observed');
      await tester.tap(
        find.byKey(
          const ValueKey('work-pr-https://github.com/acme/app/pull/12'),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://github.com/acme/app/pull/12')]);
      await tester.tap(find.byKey(const ValueKey('work-completed')));
      await tester.pumpAndSettle();
      expect(find.text('hn/nfc'), findsOneWidget);
      expect(find.text('#119'), findsOneWidget);
      expect(find.text('Keep NFC conversations in order'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureDialog(tester, boundary, 'work-completed');
    },
  );

  testWidgets(
    'completed history remains reachable beside a full open PR page',
    (tester) async {
      final git = manyPrFixture();
      final opened = <Uri>[];
      await tester.pumpWidget(
        grid.BrightnessScope(
          child: MaterialApp(
            home: Scaffold(
              body: SessionWorkDialog(
                agent: workAgent(git: git),
                online: false,
                read: (_) async => throw StateError('Offline'),
                open: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('#122'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('work-completed')));
      await tester.pumpAndSettle();
      final target = find.byKey(
        const ValueKey('work-pr-https://github.com/acme/app/pull/122'),
      );
      await tester.scrollUntilVisible(
        target,
        100,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('work-branch-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://github.com/acme/app/pull/122')]);
      final buttonContext = tester.element(
        find.descendant(of: target, matching: find.byType(Row)).first,
      );
      Focus.of(buttonContext).requestFocus();
      await tester.pumpAndSettle();
      final focus = FocusManager.instance.primaryFocus;
      final palette = grid.AppTheme.palette.value;
      final theme = terminalThemeStore.value;
      final font = terminalFontStore.value;
      addTearDown(() {
        grid.AppTheme.palette.value = palette;
        terminalThemeStore.value = theme;
        terminalFontStore.value = font;
      });
      grid.AppTheme.palette.value = HarnessPalette.midnight;
      terminalThemeStore.value = TerminalThemeChoice.tango;
      terminalFontStore.value = TerminalStyle(
        fontFamily: font.fontFamily,
        fontSize: font.fontSize + 1,
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(target.hitTestable(), findsOneWidget);
      expect(find.text('[ Hide completed ]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late replies after dismissal cannot reopen or replace another view',
    (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                focusNode: focus,
                autofocus: true,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SessionWorkDialog(
                    agent: workAgent(git: gitFixture()),
                    read: (_) => reply.future,
                  ),
                ),
                child: const Text('Inspect'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SessionWorkDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SessionWorkDialog), findsNothing);
      expect(focus.hasFocus, isTrue);
      reply.complete({'status': 'unavailable'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final palette in [HarnessPalette.graphite, HarnessPalette.midnight]) {
    for (final size in [const Size(1000, 720), const Size(420, 680)]) {
      testWidgets(
        'work details fit ${size.width} ${palette.name}, including enlarged text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final old = grid.AppTheme.palette.value;
          grid.AppTheme.palette.value = palette;
          addTearDown(() => grid.AppTheme.palette.value = old);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            grid.BrightnessScope(
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: grid.buildAppTheme(brightness: Brightness.dark),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(size.width < 500 ? 1.6 : 1),
                    ),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SessionWorkDialog(
                      agent: workAgent(git: manyPrFixture()),
                      online: false,
                      read: (_) =>
                          throw StateError('Offline must not request data'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Offline · saved data'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final output =
              Platform.environment['HARNESS_GIT_CONTEXT_CAPTURE_DIR'];
          if (output != null) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final picture = await render.toImage(pixelRatio: 1);
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/work-${size.width.toInt()}-${palette.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
        },
      );
    }
  }
}
