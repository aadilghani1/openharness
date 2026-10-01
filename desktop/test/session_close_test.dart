import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

class _CloseConnection extends WsConn {
  _CloseConnection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );
  late AppNotifier app;
  final closes = <Map<String, dynamic>>[];
  final activities = <String, String>{};
  Completer<Map<String, dynamic>>? inspecting;
  Map<String, dynamic>? failure;
  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (type != 'agent_close') return {};
    closes.add(Map.of(payload));
    final mode = payload['mode'];
    if (mode == 'inspect') {
      return inspecting?.future ??
          Future.value({'activity': activities[payload['agentId']] ?? 'idle'});
    }
    if (failure != null) return failure!;
    if (mode == 'after_task') return {'deferred': true};
    if (mode == 'cancel') return {'cancelled': true};
    await app.handleEventForTest('m', {
      'type': 'agent_deleted',
      'payload': {'agentId': payload['agentId']},
    });
    return {'closed': true};
  }
}

void main() {
  late AppNotifier app;
  late _CloseConnection connection;
  Agent agent(String id) => Agent(
    id: id,
    name: 'Work $id',
    engine: 'codex',
    sessionId: 'conversation-$id',
    createdAt: DateTime.utc(2026, 9, 30, 12),
    closeSupported: true,
    terminalAvailable: true,
    resumeMode: 'conversation',
  );
  setUp(() {
    connection = _CloseConnection();
    app = createApp(connected: true, connectionForTest: (_) => connection);
    connection.app = app;
    app.stateOf('m')!.agents = [agent('a0'), agent('a1')];
  });
  tearDown(() => app.dispose());
  List<Object?> modes() => connection.closes.map((r) => r['mode']).toList();

  test(
    'without a close presenter an unsupported decision keeps its pane intact',
    () async {
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await app.requestClosePane(pane.id);
      expect(app.panes, [pane]);
      expect(connection.closes, isEmpty);
    },
  );

  testWidgets(
    'idle Close saves the recently closed layout despite an early deleted event',
    (tester) async {
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      unawaited(app.requestClosePane(pane.id));
      await tester.pumpAndSettle();
      expect(modes(), ['inspect', 'idle']);
      expect(app.allPanes, isEmpty);
      expect(
        app.stateOf('m')!.agents.firstWhere((a) => a.id == 'a0').isStopped,
        isTrue,
      );
      expect(app.closedHistory, hasLength(1));
      expect(app.canReopenLastClosed, isTrue);
      expect(find.text('Close session'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'working Close starts with Cancel focused and Enter keeps work alive',
    (tester) async {
      connection.activities['a0'] = 'working';
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      unawaited(app.requestClosePane(pane.id));
      await tester.pumpAndSettle();
      expect(find.text('Still working. Close anyway?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Close session'), findsNothing);
      expect(find.text('Stop after finishing'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.panes, [pane]);
      expect(modes(), ['inspect']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final entry in {
    'working': 'Still working. Close anyway?',
    'needs_input': 'Waiting for input. Close anyway?',
    'draft': 'Unsent text. Close anyway?',
    'unknown': 'May still be working. Close anyway?',
  }.entries) {
    testWidgets('${entry.key} Close sends only the reviewed action', (
      tester,
    ) async {
      connection.activities['a0'] = entry.key;
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      unawaited(app.requestClosePane(pane.id));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(modes(), ['inspect']);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(modes(), ['inspect', 'now']);
      expect(app.allPanes, isEmpty);
      expect(
        app.stateOf('m')!.agents.firstWhere((a) => a.id == 'a0').isStopped,
        isTrue,
      );
      expect(app.closedHistory, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a failed disk checkpoint leaves the pane and explains why', (
    tester,
  ) async {
    connection.failure = {
      'error': 'HISTORY_NOT_SAVED',
      'detail': 'Not enough free disk space.',
    };
    final pane = app.adoptSessionForTest(terminal('a0', []));
    await mount(tester, app);
    unawaited(app.requestClosePane(pane.id));
    await tester.pumpAndSettle();
    expect(find.text('Not enough free disk space.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(app.panes, [pane]);
    expect(app.closedHistory, isEmpty);
    expect(modes(), ['inspect', 'idle']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a tab switch during an idle check cannot close the newly selected tab',
    (tester) async {
      final first = app.adoptSessionForTest(terminal('a0', []));
      final original = app.activeSwarm;
      connection.inspecting = Completer();
      await mount(tester, app);
      final closing = app.requestClosePane(first.id);
      await tester.pump();
      app.newSwarm();
      final next = app.activeSwarm;
      final second = app.adoptSessionForTest(terminal('a1', []));
      connection.inspecting!.complete({'activity': 'idle'});
      await tester.pumpAndSettle();
      await closing;
      expect(app.activeSwarm, same(next));
      expect(app.panes, [second]);
      expect(app.swarms, isNot(contains(original)));
      expect(connection.closes.every((r) => r['agentId'] == 'a0'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Close also removes the session from another hidden tab', (
    tester,
  ) async {
    final pane = app.adoptSessionForTest(terminal('a0', []));
    final original = app.activeSwarm;
    app.newSwarm();
    app.activeSwarm.panes.add(pane);
    app.activeSwarm.focusedPaneId = pane.id;
    await mount(tester, app);
    await app.requestClosePane(pane.id);
    await tester.pumpAndSettle();
    expect(modes(), ['inspect', 'idle']);
    expect(app.allPanes, isEmpty);
    expect(app.swarms, isNot(contains(original)));
    expect(
      app.stateOf('m')!.agents.firstWhere((a) => a.id == 'a0').isStopped,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Cancel on a later tab member does not stop an earlier approved member',
    (tester) async {
      connection.activities.addAll({'a0': 'working', 'a1': 'working'});
      app.adoptSessionForTest(terminal('a0', []));
      app.adoptSessionForTest(terminal('a1', []));
      await mount(tester, app);
      unawaited(app.requestCloseSwarm(app.activeSwarmId));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-close-now')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.panes, hasLength(2));
      expect(modes(), ['inspect', 'inspect']);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
