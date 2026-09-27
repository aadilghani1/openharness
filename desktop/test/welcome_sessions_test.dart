import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/state/welcome_sessions.dart';
import 'package:harness/widgets/workspace_welcome.dart';

import 'session_content_search_test.dart' show SearchConnection;
import 'swarm_state_test.dart' show createApp;

final _now = DateTime(2026, 9, 27, 12);

Map<String, dynamic> _external(
  String id,
  String title,
  Duration ago, {
  bool open = false,
}) => {
  'agentId': '',
  'sessionId': id,
  'engine': 'codex',
  'field': 'ask',
  'snippet': '',
  'together': true,
  'score': .5,
  'lastAt': _now.subtract(ago).millisecondsSinceEpoch,
  'external': {
    'title': title,
    'cwd': '/work/$id',
    'origin': 'codex-app',
    'open': open,
  },
};

Agent _agent(String id, String name, Duration ago) => Agent(
  id: id,
  sessionId: 's-$id',
  name: name,
  engine: 'claude',
  terminalAvailable: true,
  lastActivityAt: _now.subtract(ago),
);

/// A machine with three harnesses and, on its disk, three conversations
/// Harness did not start — one of them still open in a terminal.
({SearchConnection connection, WelcomeSessions sessions}) _setup() {
  final connection = SearchConnection({
    '': [
      _external('e-nfc', 'Continue NFC device chat', const Duration(hours: 2)),
      _external(
        'e-open',
        'Still open elsewhere',
        const Duration(minutes: 1),
        open: true,
      ),
      _external('e-old', 'Research local AI', const Duration(days: 6)),
    ],
  });
  final app = createApp(connected: true, connectionForTest: (_) => connection);
  app.machineStates['m']!.agents = [
    _agent('a1', 'Command palette search results', const Duration(minutes: 5)),
    _agent('a2', 'Deploy latest firmware', const Duration(days: 1)),
    _agent('a3', 'Landing page redesign', const Duration(days: 9)),
  ];
  addTearDown(app.dispose);
  final sessions = WelcomeSessions(app, now: () => _now, limit: 4);
  addTearDown(sessions.dispose);
  return (connection: connection, sessions: sessions);
}

void main() {
  test('offers harnesses and conversations Harness did not start, latest first, never one open elsewhere', () async {
    final (:connection, :sessions) = _setup();
    final loading = sessions.load();
    // The harnesses are there at once; the machines answer after.
    expect(sessions.rows.map((row) => row.agentId), ['a1', 'a2', 'a3']);
    expect(sessions.loading, isTrue);
    await loading;
    expect(sessions.loading, isFalse);
    expect(connection.asked, ['']);
    expect(sessions.rows.map((row) => row.external?.sessionId ?? row.agentId), [
      'a1',
      'e-nfc',
      'a2',
      'e-old',
    ], reason: 'by activity, capped, and not the one a terminal still has');
    final nfc = sessions.rows[1];
    expect(nfc.title, 'Continue NFC device chat');
    expect(nfc.id, externalDestinationId('m', 'e-nfc'));
  });

  testWidgets(
    'numbers, arrows, Enter and a click each open a row; other keys go on',
    (tester) async {
      final (connection: _, :sessions) = _setup();
      final app = sessions.app;
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceWelcome(
            onCommand: (_) {},
            app: app,
            onOpen: (row) =>
                opened.add(row.external?.sessionId ?? row.agentId!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('welcome-sessions')), findsOneWidget);
      expect(find.text('Pick up where you left off'), findsOneWidget);
      expect(find.text('Continue NFC device chat'), findsOneWidget);
      expect(
        find.textContaining('Codex app · e-nfc · not in Harness'),
        findsOneWidget,
      );
      expect(find.text('Still open elsewhere'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.text('Command palette search results'));
      // A number past the list, and a shortcut, are not the list's.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(opened, ['e-nfc', 'a2', 'a1']);
    },
  );

  testWidgets(
    'without an app it is the welcome it was: no list, no keys taken',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WorkspaceWelcome(onCommand: (_) {})),
      );
      expect(find.byKey(const ValueKey('welcome-sessions')), findsNothing);
      expect(find.text('Harness like a boss.'), findsOneWidget);
    },
  );

  test('fills in as machines connect and harnesses arrive at launch, and only then', () async {
    final connection = SearchConnection({
      '': [
        _external(
          'e-nfc',
          'Continue NFC device chat',
          const Duration(hours: 2),
        ),
      ],
    });
    // Launch: the machine is not connected yet, and has told us of no harness.
    final app = createApp(connectionForTest: (_) => connection);
    addTearDown(app.dispose);
    final sessions = WelcomeSessions(app, now: () => _now);
    addTearDown(sessions.dispose);
    await sessions.load();
    expect(sessions.rows, isEmpty);
    expect(connection.asked, isEmpty);

    // It connects, and its harnesses arrive.
    final machine = app.machineStates['m']!
      ..nodeOnline = true
      ..connectionStatus = ConnectionStatus.connected
      ..agents = [
        _agent(
          'a1',
          'Command palette search results',
          const Duration(minutes: 5),
        ),
      ];
    sessions.appChanged();
    await pumpEventQueue();
    expect(connection.asked, ['']);
    expect(sessions.rows.map((row) => row.external?.sessionId ?? row.agentId), [
      'a1',
      'e-nfc',
    ]);

    // After that, activity alone does not read it again.
    machine.agents = [
      _agent('a1', 'Command palette search results', Duration.zero),
    ];
    sessions.appChanged();
    await pumpEventQueue();
    expect(connection.asked, ['']);
  });
}
