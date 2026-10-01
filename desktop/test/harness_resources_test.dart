import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/harness_resources.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/harness_monitor.dart';
import 'package:harness/state/app_state.dart' show MachineState;
import 'package:harness/ws/ws_conn.dart';

import 'swarm_state_test.dart' show createApp;

class _Connection extends WsConn {
  _Connection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );
  final calls = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> reply = {
    'harnesses': {
      'sampledAt': '2026-09-30T12:00:00Z',
      'agents': [
        {
          'agentId': 'a0',
          'memoryBytes': 1400000000,
          'cpuPercent': 125.5,
          'processCount': 3,
        },
      ],
    },
  };
  @override
  bool get isReady => true;
  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls.add({'type': type, ...payload});
    return pending?.future ?? reply;
  }
}

void main() {
  test('readings preserve unknown, zero, and multi-core CPU without guessing GPU or disk', () {
    final empty = HarnessResources.fromJson({});
    expect(empty.memoryBytes, isNull);
    expect(empty.cpuPercent, isNull);
    expect(
      HarnessResources.fromJson({'cpuPercent': 125, 'memoryBytes': 0})
          .cpuPercent,
      125,
    );
    expect(formatHarnessMemory(0), '0 MB');
    expect(formatHarnessMemory(1400000000), '1.4 GB');
    for (final invalid in [-1, double.nan, double.infinity, '100']) {
      expect(
        HarnessResources.fromJson({
          'cpuPercent': invalid,
          'memoryBytes': invalid,
        }).memoryBytes,
        isNull,
      );
      expect(
        HarnessResources.fromJson({'cpuPercent': invalid}).cpuPercent,
        isNull,
      );
    }
    expect(MachineHarnessResources.parse({}), isNull);
    expect(
      MachineHarnessResources.parse({'sampledAt': 'bad', 'agents': []}),
      isNull,
    );
  });

  test('shared-server resources contribute once to totals and disappear with their last live session', () async {
    final connection = _Connection();
    final app = createApp(
      connected: true,
      connectionForTest: (_) => connection,
    );
    final monitor = HarnessMonitor(app);
    addTearDown(monitor.dispose);
    addTearDown(app.dispose);
    app.machineStates['m']!.agents = [
      const Agent(id: 'a0', name: 'Work', terminalAvailable: true),
    ];
    (connection.reply['harnesses'] as Map)['shared'] = [
      {
        'kind': 'codex',
        'agentIds': ['a0', 'another-session'],
        'memoryBytes': 600000000,
        'cpuPercent': 4.5,
        'processCount': 2,
      },
    ];
    await monitor.refresh();
    expect(monitor.label, '1 live · 2.0 GB · 130% CPU');
    expect(monitor.sharedLabel, 'Shared Codex servers · 600 MB RAM');
    expect(monitor.detail, contains('included once'));
    ((connection.reply['harnesses'] as Map)['shared'] as List).first.remove(
      'memoryBytes',
    );
    await monitor.refresh();
    expect(monitor.sharedLabel, 'Shared Codex servers · — RAM');
    expect(monitor.label, '1 live · 1.4 GB+ · 130% CPU');
    app.machineStates['m']!.agents = [];
    expect(monitor.label, '0 live');
    expect(monitor.sharedLabel, isNull);
  });

  testWidgets(
    'uses one machine request for every session; tokens are existing data',
    (tester) async {
      final connection = _Connection();
      final app = createApp(
        connected: true,
        connectionForTest: (_) => connection,
      );
      final monitor = HarnessMonitor(app);
      addTearDown(monitor.dispose);
      addTearDown(app.dispose);
      app.machineStates['m']!.agents = [
        const Agent(
          id: 'a0',
          name: 'Known work',
          terminalAvailable: true,
          tokensUsed: 9200,
        ),
        const Agent(
          id: 'hidden',
          name: 'Background work',
          terminalAvailable: true,
        ),
      ];
      expect(connection.calls, isEmpty);
      expect(
        monitor.live.length,
        2,
      ); // Inventory appears without starting or opening anything.
      await monitor.refresh();
      expect(connection.calls, [
        {'type': 'machine_resources', 'harnesses': true},
      ]);
      expect(monitor.label, '2 live · 1.4 GB+ · 126%+ CPU');
      expect(monitor.reading(monitor.live.first)!.processCount, 3);
      expect(app.allPanes, isEmpty);
      connection.reply = {};
      await monitor.refresh();
      expect(monitor.label, '2 live · — · —% CPU');
    },
  );

  testWidgets(
    'polls slowly in the footer, faster only while open, and never while hidden',
    (tester) async {
      final connection = _Connection();
      final app = createApp(
        connected: true,
        connectionForTest: (_) => connection,
      );
      final monitor = HarnessMonitor(app);
      app.machineStates['m']!.agents = [
        const Agent(id: 'a0', name: 'Work', terminalAvailable: true),
      ];
      monitor.start();
      await tester.pump();
      expect(connection.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 14));
      expect(connection.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(connection.calls, hasLength(2));
      monitor.setExpanded(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(connection.calls, hasLength(4));
      app.appLifecycleChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(minutes: 2));
      expect(connection.calls, hasLength(4));
      app.appLifecycleChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(connection.calls, hasLength(5));
      monitor.dispose();
      await tester.pump(const Duration(minutes: 2));
      expect(connection.calls, hasLength(5));
      app.dispose();
    },
  );

  testWidgets(
    'late readings cannot populate a replacement or disconnected machine',
    (tester) async {
      final connection = _Connection()..pending = Completer();
      final app = createApp(
        connected: true,
        connectionForTest: (_) => connection,
      );
      final monitor = HarnessMonitor(app);
      addTearDown(monitor.dispose);
      addTearDown(app.dispose);
      final original = app.machineStates['m']!;
      original.agents = [
        const Agent(id: 'a0', name: 'Old', terminalAvailable: true),
      ];
      final pending = monitor.refresh();
      app.machineStates['m'] = MachineState(original.machine)
        ..connectionStatus = ConnectionStatus.connected
        ..agents = [
          const Agent(id: 'a0', name: 'New', terminalAvailable: true),
        ];
      connection.pending!.complete(connection.reply);
      await pending;
      expect(monitor.label, '1 live · — · —% CPU');
      app.machineStates['m']!.connectionStatus = ConnectionStatus.disconnected;
      final before = connection.calls.length;
      await monitor.refresh();
      expect(connection.calls.length, before);
      expect(monitor.label, '0 live');
    },
  );

}
