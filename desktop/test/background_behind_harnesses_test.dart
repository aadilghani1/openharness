import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/settings/appearance/wallpaper_section.dart';
import 'package:harness/shared/theme/appearance_prefs_store.dart';
import 'package:harness/shared/theme/harness_background.dart';
import 'package:harness/widgets/box_chrome.dart';

class _Storage implements LocalKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _key = 'harness_background_behind_harnesses';

HarnessBackground get _artwork => HarnessBackground.gallery.firstWhere(
  (background) => background != HarnessBackground.plain,
);

void main() {
  group('prefs', () {
    test('off by default, at 50%', () {
      const prefs = AppearancePrefs();
      expect(prefs.behindHarnesses, isFalse);
      expect(prefs.paneOpacity, 0.5);
      expect(prefs.effectivePaneOpacity, 1);
    });

    test('round-trips through storage', () async {
      final storage = _Storage();
      final store = AppearancePrefsStore(storage: storage);
      await store.setBehindHarnesses(on: true, opacity: 0.6);

      final reloaded = AppearancePrefsStore(storage: storage);
      await reloaded.load();
      expect(reloaded.value.behindHarnesses, isTrue);
      expect(reloaded.value.paneOpacity, 0.6);
    });

    test('opacity is clamped, and garbage lands on the defaults', () async {
      final storage = _Storage();
      final store = AppearancePrefsStore(storage: storage);
      await store.setBehindHarnesses(opacity: -1);
      expect(store.value.paneOpacity, AppearancePrefs.paneOpacityMin);
      await store.setBehindHarnesses(opacity: 7);
      expect(store.value.paneOpacity, 1);

      storage.values[_key] = '{"on": "yes", "opacity": "NaN"}';
      await store.load();
      expect(store.value.behindHarnesses, isFalse);
      expect(store.value.paneOpacity, AppearancePrefs.paneOpacityDefault);

      storage.values[_key] = 'not json';
      await store.load();
      expect(store.value.behindHarnesses, isFalse);
    });

    test('Blank shows nothing behind harnesses, but keeps the choice', () async {
      final store = AppearancePrefsStore(storage: _Storage());
      await store.setBehindHarnesses(on: true, opacity: 0.7);
      expect(store.value.showsBehindHarnesses, isFalse);
      expect(store.value.effectivePaneOpacity, 1);

      await store.setBackground(_artwork);
      expect(store.value.showsBehindHarnesses, isTrue);
      expect(store.value.effectivePaneOpacity, 0.7);

      await store.setBackground(HarnessBackground.plain);
      expect(store.value.behindHarnesses, isTrue);
      expect(store.value.effectivePaneOpacity, 1);
    });

    test('reset forgets it', () async {
      final storage = _Storage();
      final store = AppearancePrefsStore(storage: storage);
      await store.setBehindHarnesses(on: true);
      await store.reset();
      expect(store.value.behindHarnesses, isFalse);
      expect(storage.values.containsKey(_key), isFalse);
    });
  });

  testWidgets('the switch shows for artwork and reveals pane opacity', (
    tester,
  ) async {
    final store = AppearancePrefsStore(storage: _Storage());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: WallpaperSection(store: store)),
        ),
      ),
    );
    final toggle = find.byKey(const ValueKey('background-behind-harnesses'));
    final slider = find.byKey(const ValueKey('background-pane-opacity'));
    expect(toggle, findsNothing, reason: 'Blank has nothing to show');

    await store.setBackground(_artwork);
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
    expect(slider, findsNothing);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.value.behindHarnesses, isTrue);
    expect(slider, findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('PaneOpacity scales fills, and is solid outside a workspace', (
    tester,
  ) async {
    late Color inside, outside;
    await tester.pumpWidget(
      Column(
        children: [
          Builder(
            builder: (context) {
              outside = PaneOpacity.fill(context, const Color(0xff202020));
              return const SizedBox();
            },
          ),
          PaneOpacity(
            opacity: 0.5,
            child: Builder(
              builder: (context) {
                inside = PaneOpacity.fill(context, const Color(0xff202020));
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
    expect(outside.a, 1);
    expect(inside.a, closeTo(0.5, 0.01));
  });
}
