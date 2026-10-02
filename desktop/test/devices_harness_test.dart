import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/devices/devices_harness_controller.dart';
import 'package:harness/settings/experimental_features.dart';
import 'package:harness/state/app_state.dart';

import 'experimental_features_test.dart' show AccountSettings;
import 'support/model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ModelManagerConnection connection;
  late ModelManagerTestApp app;
  late DevicesHarnessController devices;
  setUp(() async {
    connection = ModelManagerConnection();
    app = ModelManagerTestApp(connection);
    app.stateOf('m')!.engines.replace([
      const EngineAvailability(engine: 'codex', installed: true),
    ]);
    app.currentUser = const CurrentUserProfile(
      id: 'a',
      email: 'a@example.test',
    );
    app.experimentalFeatures.bind('a', transport: AccountSettings('a'));
    await app.experimentalFeatures.refresh();
    await app.experimentalFeatures.set(ExperimentalFeature.devicesTab, true);
    app.openDevices();
    devices = DevicesHarnessController(app);
  });
  tearDown(() {
    devices.dispose();
    app.dispose();
  });

  test(
    'waits for the existing inventory before deciding to create a conversation',
    () async {
      final loading = Completer<void>();
      final owner = app.stateOf('m')!;
      owner.agentLoadStatus = AgentLoadStatus.loading;
      owner.agentsLoadInFlight = loading.future;
      final opening = devices.open();
      expect(connection.creations, isEmpty);
      owner.agents = [
        const Agent(
          id: 'previous',
          name: 'Devices',
          engine: 'codex',
          dsh: devicesHarnessId,
          terminalAvailable: true,
        ),
      ];
      owner.agentLoadStatus = AgentLoadStatus.loaded;
      loading.complete();
      await opening;
      expect(connection.creations, isEmpty);
      expect(app.panes.any((pane) => pane.agentId == 'previous'), isTrue);
    },
  );

  test(
    'opens the bundled DSH beside its dashboard and reuses its conversation',
    () async {
      await devices.open();
      expect(devices.error, isNull);
      expect(
        connection.creations.single,
        containsPair('dsh', devicesHarnessId),
      );
      expect(
        connection.creations.single,
        containsPair('bypassPermission', false),
      );
      expect(connection.creations.single['prompt'], isNull);
      expect(app.activeSwarm.name, 'Devices');
      expect(app.panes.where((pane) => pane.isDevices), hasLength(1));
      expect(
        app.panes.where((pane) => pane.agentId == 'manager'),
        hasLength(1),
      );
      await devices.open();
      expect(connection.creations, hasLength(1));
      expect(app.panes, hasLength(2));
    },
  );
  test(
    'concurrent opens and an ambiguous creation reuse one durable request',
    () async {
      connection.holdCreation = Completer<void>();
      connection.loseFirstReply = true;
      final first = devices.open();
      expect(identical(first, devices.open()), isTrue);
      connection.holdCreation!.complete();
      await first;
      expect(devices.error, isNotNull);
      await devices.open();
      expect(devices.error, isNull);
      expect(connection.creations, hasLength(1));
      expect(app.panes, hasLength(2));
    },
  );
  test(
    'an account switch during creation cannot attach the old conversation',
    () async {
      connection.holdCreation = Completer<void>();
      final opening = devices.open();
      await Future<void>.delayed(Duration.zero);
      app.currentUser = const CurrentUserProfile(
        id: 'b',
        email: 'b@example.test',
      );
      connection.holdCreation!.complete();
      await opening;
      expect(app.swarms.any((tab) => tab.isDevices), isFalse);
      expect(app.allPanes.where((pane) => pane.agentId == 'manager'), isEmpty);
      await devices.open();
      expect(connection.creations.length, lessThanOrEqualTo(1));
    },
  );
}
