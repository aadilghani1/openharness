import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/team_page.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart' as grid;
import 'package:harness_mobile/teams/team_controller.dart';

import 'support/real_fonts.dart';
import 'support/team_fixture.dart';

void main() {
  setUpAll(loadRealFonts);
  testWidgets(
    'phone channel follows its tab with read-only history and a direct consult action',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final calls = <Map<String, dynamic>>[];
      final model = TeamController(
        channelTabId: 'devices',
        request: (p) async {
          calls.add(p);
          if (p['action'] == 'channel_cross_consult') {
            return {
              'consultation': {
                'receipt': {'state': 'queued'},
              },
            };
          }
          return {
            'team': {
              ...teamFixture(),
              'name': 'Device',
              'channel': {'tabId': 'devices'},
            },
          };
        },
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: PhoneTeamView(
              controller: model,
              machineName: 'Mac',
              candidates: const [],
              onOpen: (_, _) {},
              onConsult: () =>
                  model.consult('host', 'mobile-session', outsideSwarm: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Device'), findsOneWidget);
      expect(find.byKey(const Key('phone-team-new')), findsNothing);
      expect(find.byKey(const Key('phone-team-question')), findsNothing);
      expect(calls.map((p) => p['action']), everyElement('channel_get'));
      await tester.tap(find.text('[ Ask outside this swarm ]'));
      await tester.pumpAndSettle();
      expect(
        calls
            .where((p) => p['action'] == 'channel_cross_consult')
            .single['tabId'],
        'devices',
      );
      await tester.ensureVisible(find.textContaining('Use GET /api/daemons.'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output = Platform.environment['CHANNEL_RENDER_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/channel-phone-390.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
