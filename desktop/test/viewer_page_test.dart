import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_layout_store.dart';
import 'package:harness/state/swarm.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/viewer/viewer_location.dart';
import 'package:harness/viewer/viewer_page.dart';
import 'package:harness/widgets/link_machine_screen.dart';
import 'package:harness/widgets/web_pane_panel.dart';

import 'swarm_state_test.dart' show MemoryStore;

class _App extends AppNotifier {
  _App({MemoryStore? storage})
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(storage: MemoryStore()),
        configStore: null,
        paneLayoutStore: storage == null
            ? null
            : PaneLayoutStore(storage: storage),
        workspaceEnabled: () => false,
      );
  @override
  bool get machineInventoryLoaded => true;
  int retries = 0;
  @override
  Future<void> reloadMachineData(String machineId) async {
    retries++;
  }
}

class _Desk extends ApiClient {
  _Desk()
    : super(
        config: AppConfig.dev,
        session: AuthSession(storage: MemoryStore()),
      );
  int reads = 0;
  @override
  Future<Map<String, dynamic>?> desk() async {
    reads++;
    throw StateError('A viewer must not join the desk');
  }
}

void main() {
  test(
    'companion never restores, claims, joins or overwrites the saved desk',
    () async {
      final storage = MemoryStore();
      await PaneLayoutStore(storage: storage).saveSwarms([
        Swarm(id: 'saved', name: 'Work')
          ..panes.add(TerminalPane(id: 1, machineId: 'm', agentId: 'other')),
      ], 'saved');
      final before = Map.of(storage.values);
      final desk = _Desk();
      final app = _App(storage: storage)..api = desk;
      addTearDown(app.dispose);
      await app.restorePaneLayoutForTest(claimOnAttach: true);
      await app.deskStartForTest();
      app.newSwarm(name: 'Transient');
      await app.flushPaneLayout();
      expect(app.allPanes, isEmpty);
      expect(app.deskSyncForTest.enabled, isFalse);
      expect(desk.reads, 0);
      expect(storage.values, before);
    },
  );

  testWidgets(
    'viewer follows its named harness, requires linking and never opens a terminal',
    (tester) async {
      final app = _App();
      const machine = Machine(
        machineId: 'm',
        name: 'Render server',
        authMode: MachineAuthMode.remote,
      );
      final state = MachineState(machine)
        ..nodeOnline = true
        ..needsLink = true
        ..connectionStatus = ConnectionStatus.connected
        ..agentLoadStatus = AgentLoadStatus.loaded;
      app.machineStates['m'] = state;
      app.machines = [machine];
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: ViewerPage(
            app: app,
            location: const ViewerLocation('m', 'blender'),
          ),
        ),
      );
      await mount();
      expect(find.byType(LinkMachineScreen), findsOneWidget);
      state.needsLink = false;
      state.agents = [
        const Agent(id: 'blender', name: 'Chair', viewerName: '3D Viewer'),
      ];
      app.notifyListeners();
      await tester.pump();
      expect(find.textContaining('is starting'), findsOneWidget);
      state.agents = [
        const Agent(
          id: 'blender',
          name: 'Chair',
          viewerName: '3D Viewer',
          viewerUrl: 'http://127.0.0.1:19679/model',
        ),
      ];
      app.notifyListeners();
      await tester.pump();
      expect(find.byType(WebPanePanel), findsOneWidget);
      final pane = tester.widget<WebPanePanel>(find.byType(WebPanePanel)).pane;
      expect(pane.ownerAgentId, 'blender');
      expect(pane.agentId, isNull);
      expect(app.allPanes, isEmpty);
      state.agents = [];
      app.notifyListeners();
      await tester.pump();
      expect(find.textContaining('no longer available'), findsOneWidget);
      await tester.tap(find.textContaining('Retry'));
      await tester.pump();
      expect(app.retries, 1);
      state.nodeOnline = false;
      app.notifyListeners();
      await tester.pump();
      expect(find.text('Render server is offline.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
