import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/desk_sync.dart';
import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/widgets/engine_identity.dart';

import 'support/harness_monitor.dart';
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

class SwitchConnection extends MonitorConnection {
  late AppNotifier app;
  final events = <String>[];
  String? closeError;
  Completer<void>? holdClose;

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (type == 'agent_close') {
      events.add('save/stop');
      expect(payload['mode'], 'now');
      expect(payload['sessionId'], 'saved-conversation');
      await holdClose?.future;
      if (closeError != null) {
        return {'error': 'SAVE_FAILED', 'detail': closeError};
      }
      await app.handleEventForTest('m', {
        'type': 'agent_deleted',
        'agentId': 'a0',
        'payload': {'agentId': 'a0'},
      });
      return {'closed': true};
    }
    if (type == 'agent_create') events.add('start');
    final result = await super.request(
      type,
      payload: payload,
      timeout: timeout,
    );
    if (result['agent'] case final Map<String, dynamic> agent) {
      return {
        ...result,
        'agent': {
          ...agent,
          'engine': creations.last['engine'],
          'project': {'name': 'work', 'cwd': '/projects/work'},
          if (creations.last['dsh'] != null)
            'viewerUrl': 'http://127.0.0.1:4179/',
        },
      };
    }
    return result;
  }
}

AppNotifier fixture(
  SwitchConnection connection, {
  bool viewer = false,
  bool companion = false,
}) {
  final app = createApp(connectionForTest: (_) => connection, connected: true);
  connection.app = app;
  final source = Agent(
    id: 'a0',
    name: 'Work',
    engine: 'codex',
    sessionId: 'saved-conversation',
    createdAt: DateTime.utc(2026, 10, 1),
    closeSupported: true,
    terminalAvailable: true,
    permissionMode: 'ask',
    project: const AgentProject(name: 'work', cwd: '/projects/work'),
    dsh: companion
        ? 'autonomous/pair'
        : viewer
        ? 'test/viewer'
        : null,
    viewerUrl: viewer ? 'http://127.0.0.1:4179/' : null,
  );
  app.stateOf('m')!.agents = [source, app.stateOf('m')!.agents[1]];
  if (viewer) {
    app.stateOf('m')!.dsh.replace([
      const DshEntry(
        id: 'test/viewer',
        name: 'Viewer',
        description: '',
        engine: 'codex',
        engines: ['codex', 'opencode', 'claude'],
        installed: true,
      ),
    ]);
  }
  return app;
}

class SwitchDeskApi extends ApiClient {
  SwitchDeskApi() : super(config: AppConfig.dev, session: AuthSession());
  DeskDoc doc = const DeskDoc(revision: 0, tabs: []);
  final batches = <List<Map<String, dynamic>>>[];
  Map<String, dynamic> get json => {
    'revision': doc.revision,
    'tabs': [for (final tab in doc.tabs) tab.toJson()],
  };
  @override
  Future<Map<String, dynamic>?> desk() async => json;
  @override
  Future<Map<String, dynamic>?> deskOps(List<Map<String, dynamic>> ops) async {
    batches.add(ops);
    doc = DeskDoc(
      revision: doc.revision + 1,
      tabs: applyDeskOps(doc.tabs, ops),
    );
    return json;
  }
}

void main() {
  for (final entireTab in [true, false]) {
    test(
      'switch keeps its slot when a peer prunes ${entireTab ? 'the tab' : 'the pane'}',
      () async {
        final connection = SwitchConnection()..holdCreation = Completer<void>();
        final app = fixture(connection);
        final api = SwitchDeskApi();
        app.api = api;
        addTearDown(app.dispose);
        await app.addAgentToSwarm('m', 'a0');
        if (!entireTab) await app.addAgentToSwarm('m', 'a1');
        app.newSwarm(name: 'Peer tab');
        await app.addAgentToSwarm('m', 'a1');
        await app.deskStartForTest();
        final original = app.swarms.first;
        app.selectSwarm(original.id);
        final pane = original.panes.first;
        final sizes = Map.of(original.paneSizes);
        final switching = app.changeAgent('m', 'a0', 'claude');
        // The close is acknowledged but creation has not returned yet.
        for (var i = 0; i < 20 && connection.creations.isEmpty; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(connection.creations, hasLength(1));
        api.doc = DeskDoc(
          revision: api.doc.revision + 1,
          tabs: [
            for (final tab in api.doc.tabs)
              if (tab.id != original.id)
                tab.copyWith(name: 'Renamed remotely', nameIsCustom: true)
              else if (!entireTab)
                DeskTab(
                  id: tab.id,
                  name: tab.name,
                  nameIsCustom: tab.nameIsCustom,
                  panes: tab.panes.where((p) => p.agentId != 'a0').toList(),
                ),
          ],
        );
        api.batches.clear();
        await app.deskFetchForTest();
        await app.deskFlushForTest();
        expect(app.swarms.first, same(original));
        expect(original.panes.first, same(pane));
        expect(original.paneSizes, sizes);
        expect(app.activeSwarmId, original.id);
        expect(app.swarms.last.name, 'Renamed remotely');
        expect(
          api.doc.tabs.expand((t) => t.panes).where((p) => p.agentId == 'a0'),
          isEmpty,
        );
        connection.holdCreation!.complete();
        expect(await switching, isNull);
        await app.deskFlushForTest();
        expect(original.panes.first, same(pane));
        expect(pane.agentId, 'local-session');
        expect(
          api.doc.tabs
              .firstWhere((t) => t.id == original.id)
              .panes
              .map((p) => p.agentId),
          contains('local-session'),
        );
        expect(
          api.doc.tabs.expand((t) => t.panes).where((p) => p.agentId == 'a0'),
          isEmpty,
        );
      },
    );
  }

  test('saves before starting, then replaces every view without changing tabs or layout', () async {
    final connection = SwitchConnection();
    final app = fixture(connection, viewer: true);
    addTearDown(app.dispose);
    await app.addAgentToSwarm('m', 'a0');
    app.newSwarm(name: 'Second tab');
    await app.addAgentToSwarm('m', 'a0', swarmId: app.activeSwarmId);
    await app.addAgentToSwarm('m', 'a1');
    final panes = [...app.allPanes];
    final tabs = [...app.swarms];
    final active = app.activeSwarmId;
    final focus = app.focusedPaneId;
    final sizes = [for (final tab in tabs) Map.of(tab.paneSizes)];

    expect(await app.changeAgent('m', 'a0', 'opencode'), isNull);
    expect(connection.events, ['save/stop', 'start']);
    expect(connection.creations.single, containsPair('engine', 'opencode'));
    expect(connection.creations.single, containsPair('cwd', '/projects/work'));
    expect(connection.creations.single, containsPair('dsh', 'test/viewer'));
    expect(connection.creations.single, containsPair('permissionMode', 'ask'));
    expect(app.swarms, tabs);
    expect(app.allPanes, panes);
    expect(app.activeSwarmId, active);
    expect(app.focusedPaneId, focus);
    expect([for (final tab in tabs) tab.paneSizes], sizes);
    expect(
      app.swarms.where((s) => s.panes.any((p) => p.agentId == 'manager')),
      hasLength(2),
    );
    expect(
      app.allPanes.where((p) => p.ownerAgentId == 'manager'),
      hasLength(2),
    );
    expect(
      app.stateOf('m')!.agents.firstWhere((a) => a.id == 'a0').isStopped,
      isTrue,
    );
    expect(app.agentPreference.engineFor('test/viewer'), 'opencode');
  });

  test(
    'stopping one shared session removes its views from every tab',
    () async {
      final connection = SwitchConnection();
      final app = fixture(connection, viewer: true);
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      app.newSwarm(name: 'Second tab');
      await app.addAgentToSwarm('m', 'a0');
      await app.addAgentToSwarm('m', 'a1');
      await app.handleEventForTest('m', {
        'type': 'agent_deleted',
        'agentId': 'a0',
        'payload': {'agentId': 'a0'},
      });
      expect(
        app.swarms
            .expand((s) => s.panes)
            .where((p) => p.agentId == 'a0' || p.ownerAgentId == 'a0'),
        isEmpty,
      );
      expect(app.allPanes.single.agentId, 'a1');
    },
  );

  test('Companions saves first and keeps every pane in place', () async {
    final connection = SwitchConnection();
    final app = fixture(connection, companion: true);
    addTearDown(app.dispose);
    await app.addAgentToSwarm('m', 'a0');
    app.newSwarm(name: 'Another view');
    await app.addAgentToSwarm('m', 'a0');
    final panes = [...app.allPanes];
    expect(await app.changeAgent('m', 'a0', 'opencode'), isNotNull);
    expect(
      connection.events,
      isEmpty,
      reason: 'Bind the collection before stopping it.',
    );
    app.canChangeCompanionAgent = (machine, id) => machine == 'm' && id == 'a0';
    app.changeCompanionAgent = (source, engine) async {
      expect(connection.events, ['save/stop']);
      expect(source, 'a0');
      expect(engine, 'opencode');
      connection.inventory = [
        {
          'id': 'a0',
          'engine': 'codex',
          'dsh': 'autonomous/pair',
          'sessionId': 'saved-conversation',
          'createdAt': '2026-10-01T00:00:00.000Z',
          'status': 'stopped',
          'terminal': {'available': false},
          'project': {'cwd': '/projects/work', 'name': 'work'},
        },
        {
          'id': 'next-pair',
          'engine': engine,
          'dsh': 'autonomous/pair',
          'terminal': {'available': true},
          'project': {'cwd': '/projects/work', 'name': 'work'},
        },
      ];
      return {'ok': true, 'agentId': 'next-pair'};
    };
    expect(await app.changeAgent('m', 'a0', 'opencode'), isNull);
    expect(app.allPanes, panes);
    expect(
      app.swarms.where((s) => s.panes.any((p) => p.agentId == 'next-pair')),
      hasLength(2),
    );
    expect(
      connection.creations,
      isEmpty,
      reason: 'Companions owns its collection history.',
    );
  });

  test('a failed save leaves the agent and every pane alone; another choice can retry', () async {
    final connection = SwitchConnection()..closeError = 'Disk is full';
    final app = fixture(connection);
    addTearDown(app.dispose);
    await app.addAgentToSwarm('m', 'a0');
    final pane = app.panes.single;
    expect(await app.changeAgent('m', 'a0', 'opencode'), 'Disk is full');
    expect(connection.creations, isEmpty);
    expect(app.panes.single, same(pane));
    expect(pane.agentId, 'a0');
    connection.closeError = null;
    expect(await app.changeAgent('m', 'a0', 'claude'), isNull);
    expect(connection.creations.single['engine'], 'claude');
  });

  test('a failed launch preserves the stopped session and permits a different agent', () async {
    final connection = SwitchConnection()
      ..creationError = 'OpenCode is missing';
    final app = fixture(connection);
    addTearDown(app.dispose);
    await app.addAgentToSwarm('m', 'a0');
    final pane = app.panes.single;
    expect(
      await app.changeAgent('m', 'a0', 'opencode'),
      contains('OpenCode is missing'),
    );
    expect(pane.agentId, 'a0');
    expect(
      app.stateOf('m')!.agents.firstWhere((a) => a.id == 'a0').isStopped,
      isTrue,
    );
    connection.creationError = null;
    expect(await app.changeAgent('m', 'a0', 'claude'), isNull);
    expect(connection.events, ['save/stop', 'start', 'start']);
  });

  test(
    'concurrent switches and a lost creation reply cannot start duplicates',
    () async {
      final connection = SwitchConnection()
        ..holdClose = Completer<void>()
        ..loseFirstReply = true;
      final app = fixture(connection);
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      final first = app.changeAgent('m', 'a0', 'opencode');
      final repeated = app.changeAgent('m', 'a0', 'opencode');
      expect(identical(first, repeated), isTrue);
      connection.holdClose!.complete();
      await first;
      if (app.panes.single.agentId == 'a0') {
        expect(await app.changeAgent('m', 'a0', 'opencode'), isNull);
      }
      expect(connection.creations, hasLength(1));
      expect(app.panes.single.agentId, 'local-session');
    },
  );

  test('& searches all agents and only submits supported choices for its exact source', () {
    final connection = SwitchConnection();
    final app = fixture(connection, viewer: true);
    addTearDown(app.dispose);
    final search = SwarmSearchController(app, []);
    addTearDown(search.dispose);
    search.setQuery('&');
    expect(search.isAgentMode, isTrue);
    expect(search.rows, hasLength(allEngines.length));
    expect(search.submit(), isNull);
    search.setAgentSelection('m', 'a0');
    expect(search.rows.first.agentEngine, 'opencode');
    expect(search.submit()?.destination.agentEngine, 'opencode');
    search.setQuery('& claude');
    expect(search.rows.single.title, 'Claude Code');
    search.setQuery(
      '& ${allEngines.firstWhere((e) => !['codex', 'opencode', 'claude'].contains(e.id)).id}',
    );
    expect(search.rows.single.detail, 'Not supported by this harness');
    expect(search.submit(), isNull);
  });

  testWidgets(
    'the pane agent name opens the shared picker and cancellation leaves input alone',
    (tester) async {
      final app = createApp();
      app.stateOf('m')!.nodeOnline = true;
      app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      await tester.tap(find.byKey(const ValueKey('pane-agent-control')));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('swarm-search-input')),
      );
      expect(field.controller!.text.trim(), '&');
      expect(find.text('OpenCode'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
