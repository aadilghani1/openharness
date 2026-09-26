// Real-font review captures of the phone's daemon: the header chip in its
// states, the header with large text, the sheet (with a daemon, before one,
// and on a small phone with large text), and the hatch reveal's frames. Always
// checks that nothing overflows; writes PNGs only when asked:
//
//   HARNESS_DAEMON_CAPTURE_DIR=/tmp/daemon-phone \
//     flutter test test/daemons/daemon_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/daemons/daemon_face.dart';
import 'package:harness_mobile/daemons/render.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';
import 'package:harness_mobile/phone/daemon_chip.dart';
import 'package:harness_mobile/phone/daemon_hatch.dart';
import 'package:harness_mobile/phone/daemon_scope.dart';
import 'package:harness_mobile/phone/phone_status.dart';
import 'package:harness_mobile/phone/terminal_header.dart';
import 'package:harness_mobile/phone/terminal_header_action.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart' as grid;
import 'package:harness_mobile/state/app_state.dart';

import '../agent_pager_fixture.dart';
import 'zoo_fixture.dart';

final _output = Platform.environment['HARNESS_DAEMON_CAPTURE_DIR'];
final _roster = daemonRoster;

/// A real monospace face was found, so widths in cells mean what they will on
/// a phone.
var _realMono = false;

Future<void> _fonts() async {
  Future<bool> load(List<String> families, List<String> paths) async {
    final path = paths.where((p) => File(p).existsSync()).firstOrNull;
    if (path == null) return false;
    final bytes = ByteData.sublistView(await File(path).readAsBytes());
    for (final family in families) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    return true;
  }

  await load(
    ['.AppleSystemUIFont', 'SF Pro Text', 'Ubuntu Sans', 'Roboto'],
    [
      '/System/Library/Fonts/SFNS.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    ],
  );
  // The icons, so a capture shows them rather than tofu.
  for (final (family, asset) in [
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    (
      'packages/lucide_icons_flutter/Lucide300',
      'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
    ),
  ]) {
    try {
      final bytes = rootBundle.load(asset);
      await (FontLoader(family)..addFont(bytes)).load();
    } catch (_) {
      // Not bundled in this build: the capture shows a box instead.
    }
  }
  _realMono = await load(
    ['.AppleSystemUIFontMonospaced', 'SF Mono', 'Menlo', 'DejaVu Sans Mono'],
    [
      '/System/Library/Fonts/SFNSMono.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    ],
  );
}

Map<String, dynamic> _daemon(String id, {int xp = 600, bool shiny = false}) => {
  'id': id,
  'hatchedAt': '2026-09-26T09:42:00Z',
  'egg': 'first',
  'xp': xp,
  'shiny': shiny,
};

/// A signed-in app whose zoo is [zoo], and a host for it.
Future<AppNotifier> _app(Map<String, dynamic> zoo) async {
  final backend = FakeZooBackend()..zoo = zoo;
  final app = pagerApp(PagerConn());
  addTearDown(app.dispose);
  app.api = ZooApi(backend);
  app.zoo.ensure();
  return app;
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Size size,
  Widget child, {
  double textScale = 1,
  Future<void> Function()? then,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final before = grid.AppTheme.brightness.value;
  grid.AppTheme.brightness.value = Brightness.dark;
  addTearDown(() => grid.AppTheme.brightness.value = before);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
  await then?.call();
  await tester.pump(const Duration(milliseconds: 50));
  expect(tester.takeException(), isNull, reason: name);
  final output = _output;
  if (output == null) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// The terminal page's header with the chip in it, over a little terminal.
Widget _screen(AppNotifier app, {bool body = true, bool chip = true}) =>
    DaemonHost(
      notifier: app,
      child: Scaffold(
        backgroundColor: grid.AppPalette.windowBg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TerminalHeader(
                agent: Agent.fromJson({
                  'id': 'a',
                  'engine': 'claude',
                  'name': 'Fix login redirect',
                  'project': {'name': 'harness', 'cwd': '/work/harness'},
                }),
                status: (label: 'Live', tone: PhoneTone.good),
                machineName: 'studio',
                trailing: [
                  if (chip)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: DaemonChip(),
                    ),
                  TerminalHeaderAction(
                    icon: LucideIcons.ellipsisVertical300,
                    tooltip: 'Harness actions',
                    last: true,
                    onPressed: () {},
                  ),
                ],
              ),
              const TerminalHeaderRule(busy: false),
              if (body)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '> fix the login redirect\n\n'
                      '  Reading src/auth/redirect.ts\n'
                      '  Editing 2 files\n',
                      style: TextStyle(
                        fontFamily: grid.AppFont.mono,
                        fontSize: 13,
                        color: grid.AppPalette.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

DaemonHostState _host(WidgetTester tester) =>
    tester.state<DaemonHostState>(find.byType(DaemonHost));

void main() {
  setUpAll(_fonts);

  const header = Size(390, 64);
  const phone = Size(390, 844);

  testWidgets('chip: idle, need, work, fail, boop', (tester) async {
    for (final (name, watch) in [
      ('idle', const DaemonWatch()),
      ('need', const DaemonWatch(needs: {'m/a#q'})),
      ('work', const DaemonWatch(working: {'m/a'})),
      ('fail', const DaemonWatch(failing: {'m/a'})),
    ]) {
      final app = await _app({
        'daemons': [_daemon('tim')],
        'pair': 'tim',
      });
      await _capture(
        tester,
        'chip-tim-$name',
        header,
        _screen(app, body: false),
        then: () async {
          await tester.pump();
          final face = _host(tester).face;
          face.sync(const DaemonWatch());
          face.sync(watch);
          face.pulse();
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    }
  });

  testWidgets('header: large text grows the row, with and without the chip', (
    tester,
  ) async {
    for (final (name, size, scale, chip) in [
      ('header-320-large-text', const Size(320, 96), 1.5, true),
      ('header-320-large-text-no-chip', const Size(320, 96), 1.5, false),
      ('header-390-larger-text', const Size(390, 110), 2.0, true),
    ]) {
      final app = await _app({
        'daemons': [_daemon('tim')],
        'pair': 'tim',
      });
      await _capture(
        tester,
        name,
        size,
        _screen(app, body: false, chip: chip),
        textScale: scale,
      );
      expect(
        tester.getSize(find.byType(TerminalHeader)).height,
        TerminalHeader.heightFor(TextScaler.linear(scale)) - 1,
        reason: name,
      );
    }
  });

  testWidgets('chip: every daemon at 2.0 and 0.1', (tester) async {
    for (final d in _roster.daemons) {
      for (final (version, xp) in [('2.0', 600), ('0.1', 0)]) {
        final app = await _app({
          'daemons': [_daemon(d.id, xp: xp)],
          'pair': d.id,
        });
        await _capture(
          tester,
          'chip-${d.id}-$version',
          header,
          _screen(app, body: false),
        );
      }
    }
  });

  testWidgets('chip: the nest, and the egg ready', (tester) async {
    for (final (name, habits, eggs) in [
      ('nest-1', ['turn'], <Map<String, dynamic>>[]),
      ('nest-4', ['turn', 'split', 'find', 'store'], <Map<String, dynamic>>[]),
      (
        'egg-ready',
        ['turn', 'split', 'find', 'store', 'resume'],
        [
          {'id': 'e0', 'kind': 'first', 'grantedAt': ''},
        ],
      ),
    ]) {
      final app = await _app({
        'daemons': const [],
        'eggs': eggs,
        'habits': habits,
      });
      await _capture(tester, 'chip-$name', header, _screen(app, body: false));
    }
  });

  testWidgets('sheet: a daemon, its shelf and eggs', (tester) async {
    final app = await _app({
      'daemons': [
        _daemon('tim'),
        _daemon('vim', xp: 150),
        _daemon('fzf', xp: 0, shiny: true),
        _daemon('grue', xp: 0),
      ],
      'eggs': [
        {'id': 'e1', 'kind': 'week', 'grantedAt': ''},
        {'id': 'e2', 'kind': 'night', 'grantedAt': ''},
      ],
      'pair': 'tim',
      'habits': const ['turn', 'split', 'find', 'machine', 'store'],
      'firstEgg': true,
    });
    Future<void> open() async {
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('daemon-chip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
    }

    await _capture(tester, 'sheet-tim', phone, _screen(app), then: open);
    await _capture(
      tester,
      'sheet-tim-scrolled',
      phone,
      _screen(app),
      then: () async {
        await open();
        await tester.drag(
          find.byKey(const ValueKey('daemon-sheet')),
          const Offset(0, -1200),
        );
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
    await _capture(
      tester,
      'sheet-tim-320-large-text',
      const Size(320, 640),
      _screen(app),
      textScale: 1.5,
      then: open,
    );
  });

  testWidgets('sheet: the nest before any daemon', (tester) async {
    final app = await _app({
      'daemons': const [],
      'eggs': const [],
      'habits': const ['turn', 'split', 'find'],
    });
    await _capture(
      tester,
      'sheet-nest',
      phone,
      _screen(app),
      then: () async {
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('daemon-chip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });

  testWidgets('reveal: every stage, a secret, a shiny legendary', (
    tester,
  ) async {
    final app = await _app(const {'daemons': []});
    Future<void> reveal(
      String name,
      String id,
      HatchFrame frame, {
      bool shiny = false,
      Size size = phone,
      String kind = 'first',
    }) => _capture(
      tester,
      'reveal-$name',
      size,
      DaemonHatchReveal(
        roster: _roster,
        egg: ZooEgg(id: 'e', kind: kind, grantedAt: ''),
        result: Future.value(ZooHatch(eggId: 'e', daemonId: id, shiny: shiny)),
        zoo: app.zoo,
        still: frame,
      ),
    );

    final tim = _roster.byId('tim')!;
    final sprite = renderSprite(_roster, tim, 0, DaemonMood.idle);
    await reveal(
      '1-egg',
      'tim',
      HatchFrame(stage: HatchStage.egg, egg: eggFrame(_roster, offset: -1)),
    );
    await reveal(
      '2-crack',
      'tim',
      HatchFrame(stage: HatchStage.egg, egg: eggFrame(_roster, crack: 2)),
    );
    await reveal(
      '3-pop',
      'tim',
      HatchFrame(stage: HatchStage.egg, egg: eggPopFrame(_roster)),
    );
    await reveal(
      '4-silhouette',
      'tim',
      HatchFrame(stage: HatchStage.silhouette, sprite: silhouette(sprite)),
    );
    await reveal(
      '5-colour-blink',
      'tim',
      HatchFrame(
        stage: HatchStage.colour,
        sprite: renderSprite(_roster, tim, 0, DaemonMood.idle, lid: '-'),
      ),
    );
    final timRows = renderBanner(daemonBanner, 'tim').length;
    await reveal(
      '6-banner-typing',
      'tim',
      HatchFrame(stage: HatchStage.banner, sprite: sprite, bannerRows: 2),
    );
    await reveal(
      '6-banner',
      'tim',
      HatchFrame(stage: HatchStage.banner, sprite: sprite, bannerRows: timRows),
    );
    await reveal(
      '7-card',
      'tim',
      HatchFrame(stage: HatchStage.card, sprite: sprite, bannerRows: timRows),
    );
    await reveal(
      '7-card-320',
      'tim',
      HatchFrame(stage: HatchStage.card, sprite: sprite, bannerRows: timRows),
      size: const Size(320, 568),
    );
    await reveal(
      'grue-pitch',
      'grue',
      const HatchFrame(stage: HatchStage.pitch),
      kind: 'night',
    );
    final grue = _roster.byId('grue')!;
    final grueSprite = renderSprite(_roster, grue, 0, DaemonMood.idle);
    await reveal(
      'grue-card',
      'grue',
      HatchFrame(
        stage: HatchStage.card,
        sprite: grueSprite,
        bannerRows: renderBanner(daemonBanner, 'grue').length,
      ),
      kind: 'night',
    );
    final fzf = _roster.byId('fzf')!;
    await reveal(
      'fzf-shiny-card',
      'fzf',
      HatchFrame(
        stage: HatchStage.card,
        sprite: renderSprite(_roster, fzf, 0, DaemonMood.idle),
        bannerRows: renderBanner(daemonBanner, 'fzf').length,
      ),
      shiny: true,
      kind: 'marathon',
    );
  });

  testWidgets('reveal: every name fits a 320pt screen at full size', (
    tester,
  ) async {
    if (!_realMono) {
      markTestSkipped('no real monospace face on this machine');
      return;
    }
    final app = await _app(const {'daemons': []});
    final banner = find.byKey(const ValueKey('daemon-hatch-banner'));
    for (final d in _roster.daemons) {
      final rows = renderBanner(daemonBanner, d.id);
      await _capture(
        tester,
        'banner-${d.id}-320',
        const Size(320, 568),
        DaemonHatchReveal(
          key: ValueKey(d.id),
          roster: _roster,
          egg: const ZooEgg(id: 'e', kind: 'first', grantedAt: ''),
          result: Future.value(
            ZooHatch(eggId: 'e', daemonId: d.id, shiny: false),
          ),
          zoo: app.zoo,
          still: HatchFrame(
            stage: HatchStage.banner,
            sprite: renderSprite(_roster, d, 0, DaemonMood.idle),
            bannerRows: rows.length,
          ),
        ),
      );
      // Drawn at its own size: not scaled down, and inside the margins.
      final drawn = tester.getRect(banner);
      expect(drawn.width, closeTo(tester.getSize(banner).width, .01));
      expect(drawn.left, greaterThanOrEqualTo(20));
      expect(drawn.right, lessThanOrEqualTo(300));
    }
  });
}
