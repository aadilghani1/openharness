@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/desktop_window.dart';
import 'package:harness/core/harness_file_store.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/test_run.dart';
import 'package:harness/core/viewer_mode.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/state/grid_pictures.dart';
import 'package:harness/terminal/terminal_font_store.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'a late model response cannot cross an account change in JavaScript',
    () {
      final pictures = GridPictures();
      addTearDown(pictures.dispose);
      final response = GridModels.fromReply({'models': []});
      pictures.adopt('machine', response);
      final oldEpoch = pictures.epochOf('machine');
      pictures.clear();
      expect(pictures.adopt('machine', response, ifEpoch: oldEpoch), isFalse);
      expect(pictures['machine'], isNull);
    },
  );

  test(
    'browser persists preferences and isolates credentials to the tab',
    () async {
      final store = HarnessFileStore.shared;
      const pref = 'test_browser_preference',
          credential = 'auth_test_browser_token';
      addTearDown(() async {
        await store.delete(pref);
        await store.delete(credential);
      });
      await store.write(pref, 'large');
      await store.write(credential, 'synthetic');
      expect(await store.readMany([pref, credential]), {
        pref: 'large',
        credential: 'synthetic',
      });
      expect(web.window.localStorage.getItem('harness.web.v1.$pref'), 'large');
      expect(
        web.window.localStorage.getItem('harness.web.v1.$credential'),
        isNull,
      );
      expect(
        web.window.sessionStorage.getItem('harness.web.v1.$credential'),
        'synthetic',
      );
      await store.delete(credential);
      expect(await store.read(credential), isNull);
    },
  );

  testWidgets('the desktop workspace and command picker mount in the browser', (
    tester,
  ) async {
    expect(
      kUnderTest,
      isTrue,
      reason: 'Run with --dart-define=HARNESS_TEST=true',
    );
    expect(kViewerMode, isTrue);
    expect(hasManagedWindow, isFalse);
    expect(
      TerminalFontChoice.defaultForPlatform,
      TerminalFontChoice.robotoMono,
    );
    final app = AppNotifier(config: AppConfig.dev, authSession: AuthSession())
      ..newSwarm(newTabPage: true);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        home: SwarmScreen(notifier: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Harness like a boss.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final tabs = app.swarms.length;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect(app.swarms.length, tabs + 1);
    const modifier = LogicalKeyboardKey.altLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('swarm-search-input')), findsOneWidget);
    expect(find.textContaining('No harnesses yet.'), findsOneWidget);
    expect(find.textContaining('This tab is full'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
