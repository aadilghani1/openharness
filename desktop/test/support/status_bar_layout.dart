// The Flutter status bar's geometry, for comparing the bar with daemons off
// against the bar from before daemons existed
// (test/fixtures/status_bar_before_daemons.json).
//
// Only what both versions have is read, so the same code measures either:
// every control in the bar (tabs, the new-tab button, the model picker) and
// the focused pane's context, in the default test font.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/workspace_bar_control.dart';

import '../swarm_screen_test.dart' show terminal;

/// The widths compared, from a narrow window to a wide one.
const statusBarWidths = [480.0, 720.0, 1024.0, 1280.0, 1728.0];

/// Five tabs, a harness in each, signed in with a profile.
void seedStatusBarWorkspace(AppNotifier app) {
  app.currentUser = const CurrentUserProfile(
    id: 'u1',
    email: 'layout@example.test',
  );
  app.adoptSessionForTest(terminal('a0', []));
  for (var i = 1; i < 5; i++) {
    app.newSwarm();
    app.adoptSessionForTest(terminal('a$i', []));
  }
}

/// `{width: [[left, top, width, height], ...]}`: the bar, then each control
/// in it in order, then the focused context.
Future<Map<String, List<List<double>>>> measureStatusBar(
  WidgetTester tester,
) async {
  final out = <String, List<List<double>>>{};
  List<double> box(Rect r) => [
    for (final v in [r.left, r.top, r.width, r.height])
      (v * 100).roundToDouble() / 100,
  ];
  for (final width in statusBarWidths) {
    tester.view.physicalSize = Size(width, 800);
    await tester.pump(const Duration(milliseconds: 100));
    final bar = find.byKey(const ValueKey('workspace-status-bar'));
    out['${width.toInt()}'] = [
      box(tester.getRect(bar)),
      for (final element
          in find
              .descendant(of: bar, matching: find.byType(WorkspaceBarControl))
              .evaluate())
        box(tester.getRect(find.byWidget(element.widget))),
      box(tester.getRect(find.byKey(const ValueKey('workspace-pane-context')))),
    ];
  }
  return out;
}
