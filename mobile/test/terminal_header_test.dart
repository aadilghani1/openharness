import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/daemon_chip.dart';
import 'package:harness_mobile/phone/daemon_scope.dart';
import 'package:harness_mobile/phone/phone_status.dart';
import 'package:harness_mobile/phone/status_pill.dart';
import 'package:harness_mobile/phone/terminal_header.dart';
import 'package:harness_mobile/phone/terminal_header_action.dart';
import 'package:harness_mobile/phone/terminal_place_line.dart';

import 'agent_pager_fixture.dart';
import 'daemons/zoo_fixture.dart';

/// The terminal's top bar: *agent* over *folder ⑂ branch*, with the
/// connection state as a dot on the engine mark.
void main() {
  group('the sheet names the folder with its parent, the rest folded', () {
    for (final (cwd, label) in [
      (
        '/Users/dudu/Bitcoin_builder/Grid/autonomous-harness/mobile',
        '~/…/autonomous-harness/mobile',
      ),
      ('/home/tony/work/harness', '~/work/harness'),
      ('/Users/dudu/notes', '~/notes'),
      ('/Users/dudu', '~'),
      ('/root/a/b/c', '~/…/b/c'),
      ('/srv/app', '/srv/app'),
      ('/opt/tools/grid', '/…/tools/grid'),
      (r'C:\Users\tony\code\harness', 'C:/…/code/harness'),
      ('/', '/'),
    ]) {
      test('$cwd → $label', () => expect(projectPathTrail(cwd), label));
    }
  });

  Future<void> pumpHeader(WidgetTester tester, Map<String, dynamic> wire) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalHeader(
              agent: Agent.fromJson({'id': 'a', 'engine': 'claude', ...wire}),
              status: (label: 'Live', tone: PhoneTone.good),
              machineName: 'MacBookPro2021.local',
            ),
          ),
        ),
      );

  testWidgets('two lines, and the state on the mark', (tester) async {
    await pumpHeader(tester, {
      'name': 'api',
      'project': {
        'name': 'autonomous-harness',
        'cwd': '/Users/dudu/Bitcoin_builder/Grid/autonomous-harness',
        'branch': 'feat/mobile-ios-android',
      },
    });

    expect(find.text('api'), findsOneWidget);
    // The desktop's order: the machine, the folder, the branch.
    final place = [
      for (final text in tester.widgetList<Text>(find.byType(Text))) text.data,
    ];
    expect(
      place,
      containsAllInOrder([
        'MacBookPro2021.local',
        'autonomous-harness',
        'feat/mobile-ios-android',
      ]),
    );
    // No word for the state — the dot says it, and its tooltip.
    expect(find.text('Live'), findsNothing);
    expect(find.byType(StatusDot), findsOneWidget);
    expect(find.byTooltip('Live'), findsOneWidget);
  });

  testWidgets('reads as the desktop\'s pane header does', (tester) async {
    await pumpHeader(tester, {
      'name': 'harness-3',
      'title': 'Worktree and branches organization',
      'project': {
        'name': 'autonomous-harness',
        'cwd': '/Users/dudu/.harness/worktrees/worktree-35ab',
        'root': '/Users/dudu/.harness/worktrees/worktree-35ab',
        'branch': 'harness/3',
        'branchPending': true,
      },
    });

    // The session's title over the CLI's made-up name, the repository over the worktree's
    // folder, and no branch while Harness's placeholder waits for the session's name.
    expect(find.text('Worktree and branches organization'), findsOneWidget);
    expect(find.text('autonomous-harness'), findsOneWidget);
    expect(find.text('worktree-35ab'), findsNothing);
    expect(find.text('harness/3'), findsNothing);
  });

  group('large text: the row grows to its two lines, nothing overflows', () {
    final agent = Agent.fromJson({
      'id': 'a',
      'engine': 'claude',
      'name': 'Fix the login redirect on every machine',
      'project': {
        'name': 'autonomous-harness',
        'cwd': '/work/autonomous-harness',
        'branch': 'feat/mobile-ios-android',
      },
    });

    for (final (width, scale) in [
      (390.0, 1.0),
      (390.0, 1.5),
      (320.0, 1.5),
      (320.0, 2.0),
    ]) {
      for (final chip in [false, true]) {
        final name =
            '${width.toInt()}pt at ${scale}x, '
            '${chip ? 'with' : 'without'} the daemon chip';
        testWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 400);
          addTearDown(tester.view.reset);
          final app = pagerApp(PagerConn());
          addTearDown(app.dispose);
          if (chip) {
            app.api = ZooApi(FakeZooBackend());
            app.zoo.ensure();
          }
          final header = TerminalHeader(
            key: const ValueKey('header'),
            agent: agent,
            status: (label: 'Live', tone: PhoneTone.good),
            machineName: 'MacBookPro2021.local',
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
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: DaemonHost(
                notifier: app,
                // Over the terminal, as the page lays it: nothing bounds its
                // height.
                child: Scaffold(
                  body: Stack(
                    children: [
                      Positioned(top: 0, left: 0, right: 0, child: header),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('daemon-chip')),
            chip ? findsOneWidget : findsNothing,
          );

          final row = tester.getRect(find.byKey(const ValueKey('header')));
          final title = tester.getRect(find.text(agent.displayName));
          final place = tester.getRect(find.byType(TerminalPlaceLine));
          // Both lines sit inside the row, whatever the text size.
          expect(title.top, greaterThanOrEqualTo(row.top));
          expect(place.bottom, lessThanOrEqualTo(row.bottom));
          expect(title.right, lessThanOrEqualTo(row.right));
          // It grows only as far as its lines need, and never below its
          // own 40pt.
          final height = TerminalHeader.heightFor(TextScaler.linear(scale));
          expect(row.height, height - 1);
          if (scale == 1) {
            expect(height, TerminalHeader.height);
          } else {
            expect(height, greaterThan(TerminalHeader.height));
          }
        });
      }
    }
  });

  group('the second line shares out only what overruns it', () {
    // Machine, folder, branch — the order they are drawn in, and the order each gives way in.
    const givesWay = [1, 2, 0];

    test('everything whole where it fits', () {
      expect(
        placeWidths(wanted: [100, 90, 80], givesWay: givesWay, free: 300),
        [100, 90, 80],
      );
    });

    test('the branch gives way first, then the machine; the folder last', () {
      expect(
        placeWidths(wanted: [100, 90, 80], givesWay: givesWay, free: 250),
        [100, 90, 60],
      );
      expect(
        placeWidths(wanted: [100, 90, 80], givesWay: givesWay, free: 200),
        [56, 90, kPlaceFloor],
      );
    });

    test('below the floors only once every name is down to its own', () {
      // Then in the same order: the branch first again.
      expect(
        placeWidths(wanted: [100, 90, 80], givesWay: givesWay, free: 150),
        [kPlaceFloor, kPlaceFloor, 42],
      );
    });
  });
}
