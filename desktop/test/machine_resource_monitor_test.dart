import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/machine_resources.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/state/machine_resource_monitor.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/widgets/machine_resource_panel.dart';
import 'package:harness/widgets/workspace_machine_resources.dart';

import 'support/real_fonts.dart';
import 'workspace_status_test.dart' show captureControls;

class _App extends AppNotifier {
  _App()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      ) {
    for (final (id, name) in [
      ('m', 'M2'),
      ('o', 'office'),
      ('r', '4090 Rig'),
    ]) {
      machineStates[id] =
          MachineState(
              Machine(
                machineId: id,
                name: name,
                authMode: MachineAuthMode.remote,
              ),
            )
            ..nodeOnline = true
            ..connectionStatus = ConnectionStatus.connected;
    }
    machineStates['shared'] = MachineState(
      const Machine(
        machineId: 'shared',
        name: 'Shared',
        isShared: true,
        authMode: MachineAuthMode.remote,
      ),
    )..connectionStatus = ConnectionStatus.connected;
    selectedMachineId = 'm';
  }
  final calls = <String>[];
  final values = <String, MachineResources?>{
    'm': const MachineResources(
      cpuPercent: 20,
      memoryUsedBytes: 16000000000,
      memoryTotalBytes: 32000000000,
      memoryPressure: 'normal',
      swapUsedBytes: 0,
      diskFreeBytes: 320000000000,
      diskTotalBytes: 500000000000,
      gpus: [
        MachineGpu(id: 'apple', name: 'Apple GPU', utilizationPercent: 10),
      ],
    ),
    'o': const MachineResources(
      cpuPercent: 35,
      memoryUsedBytes: 48000000000,
      memoryTotalBytes: 64000000000,
    ),
    'r': const MachineResources(
      cpuPercent: 40,
      memoryUsedBytes: 32000000000,
      memoryTotalBytes: 64000000000,
      gpus: [
        MachineGpu(id: 'a', name: 'RTX 4090 #1', utilizationPercent: 80),
        MachineGpu(id: 'b', name: 'RTX 4090 #2', utilizationPercent: 60),
      ],
    ),
  };
  Completer<MachineResources?>? pending;
  @override
  Future<MachineResources?> readMachineResources(String machineId) async {
    calls.add(machineId);
    return pending?.future ?? values[machineId];
  }

  void changed() => notifyListeners();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['HARNESS_WORKSPACE_CONTROLS_CAPTURE_DIR'] !=
        null) {
      await loadRealFonts();
      await (FontLoader('packages/lucide_icons_flutter/Lucide400')..addFont(
            rootBundle.load(
              'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w400.ttf',
            ),
          ))
          .load();
    }
  });

  testWidgets(
    'scope follows the focused pane; choosing a machine pins it without navigation',
    (tester) async {
      final app = _App();
      final monitor = MachineResourceMonitor(app);
      app.activeSwarm.panes.addAll([
        TerminalPane(id: 1, machineId: 'm', agentId: 'a'),
        TerminalPane(id: 2, machineId: 'o', agentId: 'b'),
      ]);
      app.focusedPaneId = 1;
      monitor.start();
      await tester.pump();
      expect(monitor.scopeName, 'M2');
      expect(monitor.label, 'M2    CPU  20%    RAM  50%    GPU  10%');
      app.focusedPaneId = 2;
      app.changed();
      await tester.pump();
      expect(monitor.scopeName, 'office');
      monitor.selectMachine('r');
      await tester.pump();
      expect(monitor.followsFocus, isFalse);
      expect(
        monitor.reading(monitor.selected)!.busiestGpu!.utilizationPercent,
        80,
      );
      expect(app.focusedPaneId, 2);
      app.focusedPaneId = 1;
      app.changed();
      expect(monitor.scopeName, '4090 Rig');
      monitor.selectMachine(null);
      await tester.pump();
      expect(monitor.scopeName, 'M2');
      expect(monitor.followsFocus, isTrue);
      expect(app.allPanes, hasLength(2));
      monitor.dispose();
      app.dispose();
    },
  );

  testWidgets(
    'polls only the selected host at rest, all owned hosts when open, none while hidden',
    (tester) async {
      final app = _App();
      final monitor = MachineResourceMonitor(app)..start();
      await tester.pump();
      expect(app.calls, ['m']);
      await tester.pump(const Duration(seconds: 14));
      expect(app.calls, ['m']);
      await tester.pump(const Duration(seconds: 1));
      expect(app.calls, ['m', 'm']);
      monitor.setExpanded(true);
      await tester.pump();
      expect(app.calls.skip(2).toSet(), {'m', 'o', 'r'});
      await tester.pump(const Duration(seconds: 3));
      expect(app.calls, hasLength(8));
      app.appLifecycleChanged(AppLifecycleState.hidden);
      expect(monitor.reading(monitor.selected), isNull);
      await tester.pump(const Duration(minutes: 2));
      expect(app.calls, hasLength(8));
      app.appLifecycleChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(app.calls, hasLength(11));
      monitor.setExpanded(false);
      await tester.pump();
      expect(app.calls.last, 'm');
      final count = app.calls.length;
      await tester.pump(const Duration(seconds: 3));
      expect(app.calls, hasLength(count));
      expect(app.allPanes, isEmpty);
      monitor.dispose();
      await tester.pump(const Duration(minutes: 1));
      expect(app.calls, hasLength(count));
      app.dispose();
    },
  );

  testWidgets(
    'offline, removed and replacement machines cannot retain a stale reading',
    (tester) async {
      final app = _App();
      final monitor = MachineResourceMonitor(app)..start();
      await tester.pump();
      expect(monitor.reading(monitor.selected), isNotNull);
      monitor.selectMachine('m');
      await tester.pump();
      app.machineStates['m']!.connectionStatus = ConnectionStatus.disconnected;
      app.changed();
      await tester.pump();
      expect(monitor.scopeName, 'M2');
      expect(monitor.reading(monitor.selected), isNull);
      expect(monitor.detail, contains('Machine disconnected'));
      final before = app.calls.length;
      await monitor.refresh();
      expect(app.calls, hasLength(before));
      app.machineStates['m']!.connectionStatus = ConnectionStatus.connected;
      app.pending = Completer();
      app.changed();
      await tester.pump();
      app.machineStates['m'] = MachineState(app.machineStates['m']!.machine)
        ..connectionStatus = ConnectionStatus.connected;
      app.pending!.complete(const MachineResources(cpuPercent: 99));
      await tester.pump();
      expect(monitor.reading(monitor.selected), isNull);
      app.pending = null;
      app.machineStates.remove('m');
      app.changed();
      await tester.pump();
      expect(monitor.followsFocus, isTrue);
      expect(monitor.selected!.machine.machineId, isNot('m'));
      expect(monitor.machines.any((s) => s.machine.isShared), isFalse);
      monitor.dispose();
      app.dispose();
    },
  );

  for (final (width, scale, brightness) in [
    (520.0, 1.0, Brightness.dark),
    (520.0, 1.0, Brightness.light),
    (320.0, 2.0, Brightness.dark),
  ]) {
    testWidgets(
      'resource panel stays usable at width $width and text scale $scale in $brightness',
      (tester) async {
        final app = _App();
        final monitor = MachineResourceMonitor(app)..setExpanded(true);
        await monitor.refresh();
        addTearDown(monitor.dispose);
        addTearDown(app.dispose);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 700);
        addTearDown(tester.view.reset);
        var closed = false;
        final originalBrightness = grid.AppTheme.brightness.value;
        grid.AppTheme.brightness.value = brightness;
        addTearDown(() => grid.AppTheme.brightness.value = originalBrightness);
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = shadows);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: grid.buildAppTheme(brightness: brightness),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 600),
                      child: MachineResourcePanel(
                        monitor: monitor,
                        onClose: () => closed = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Memory pressure'), findsOneWidget);
        await captureControls(
          tester,
          'machine-resources-$width-$scale-${brightness.name}',
        );
        debugDisableShadows = shadows;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(monitor.scopeName, 'office');
        expect(monitor.followsFocus, isFalse);
        await tester.tap(find.byKey(const ValueKey('resource-follow-focus')));
        await tester.pump();
        expect(monitor.followsFocus, isTrue);
        expect(monitor.scopeName, 'M2');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(closed, isTrue);
        expect(app.allPanes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'footer hides complete groups at narrow widths and retains full details in its tooltip',
    (tester) async {
      final app = _App();
      final monitor = MachineResourceMonitor(app);
      await monitor.refresh();
      addTearDown(monitor.dispose);
      addTearDown(app.dispose);
      for (final width in [500.0, 270.0, 120.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: WorkspaceMachineResources(
                    monitor: monitor,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('M2'), findsOneWidget);
        expect(
          tester.widget<Tooltip>(find.byType(Tooltip).first).message,
          contains('GPU  10%'),
        );
        final metricText = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join();
        if (width == 500) expect(metricText, contains('GPU'));
        if (width == 120) expect(metricText, isNot(contains('CPU')));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
