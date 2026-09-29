import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/notify/alert_sounds.dart';
import 'package:harness/state/notification_inbox.dart';
import 'package:harness/state/status_menu.dart';

import 'swarm_attention_test.dart' show waitingQuestion;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  test('lists every unread harness and excludes recent sessions without notifications', () {
    final app = createApp(connected: true);
    addTearDown(app.dispose);
    for (var i = 0; i < 30; i++) {
      app.rememberOpenedHarness('m', 'a$i');
      if (i >= 10) app.agentUnread.mark('m', 'a$i', AlertKind.done);
    }
    final entries = statusMenuEntries(app);
    expect(entries, hasLength(20));
    expect(entries.every((r) => r['unread'] == true), isTrue);
    expect(entries.any((r) => r['agentId'] == 'a0'), isFalse);
    expect(entries.map((r) => r['agentId']).toSet(), hasLength(entries.length));
    expect(entries.first['agentId'], 'a29');
    expect(entries.first['project'], 'No Project');
    expect(entries.first['machineName'], 'Test host');
    expect(entries.first['unavailable'], isNull);
    app.stateOf('m')!.nodeOnline = false;
    expect(statusMenuEntries(app).first['unavailable'], 'Offline');
    clearStatusMenuNotifications(app, entries);
    expect(
      statusMenuEntries(app),
      isEmpty,
      reason: 'read conversations never fill an empty notification menu',
    );
  });

  test(
    'clear acknowledges displayed news, never answers or clears newer news',
    () {
      final app = createApp(connected: true);
      addTearDown(app.dispose);
      final machine = app.stateOf('m')!;
      app.agentUnread.mark('m', 'a0', AlertKind.done);
      machine.blockedAgents['a1'] = waitingQuestion('a1');
      app.agentUnread.mark('m', 'a1', AlertKind.needsYou);
      app.rememberOpenedHarness('m', 'a2');
      machine.blockedAgents['a2'] = waitingQuestion('a2', requestId: 'old');
      final displayed = statusMenuEntries(app);
      expect(displayed.where((r) => r['unread'] == true), hasLength(3));

      app.agentUnread.mark('m', 'a0', AlertKind.done, fresh: true);
      app.agentUnread.mark('m', 'a3', AlertKind.failed);
      machine.blockedAgents['a2'] = waitingQuestion('a2', requestId: 'new');
      clearStatusMenuNotifications(app, displayed);

      expect(notificationInbox(app).map((r) => r.agentId).toSet(), {
        'a0',
        'a2',
        'a3',
      });
      expect(app.questionFor('m', 'a1'), isNotNull);
      expect(app.questionNotificationRead('m', 'a1'), isTrue);
      clearStatusMenuNotifications(app, statusMenuEntries(app));
      expect(notificationInbox(app), isEmpty);
      expect(machine.blockedAgents.keys, containsAll(['a1', 'a2']));
    },
  );

  testWidgets(
    'native menu reuses panes, rejects stale clicks and clears its snapshot',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      const windowChannel = MethodChannel('window_manager');
      final updates = <Map>[];
      final windowActions = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'update') updates.add(call.arguments as Map);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(windowChannel, (call) async {
        windowActions.add(call.method);
        return call.method == 'isMinimized' ? true : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(windowChannel, null),
      );
      final app = createApp(connected: true)..watchedAgents = () => const [];
      final resultTab = app.activeSwarmId;
      final result = app.adoptSessionForTest(terminal('a8', []));
      app.newSwarm(name: 'Desktop');
      app.adoptSessionForTest(terminal('a0', []));
      final originalTab = app.activeSwarmId;
      app.agentUnread.mark('m', 'a8', AlertKind.done);
      app.stateOf('m')!.blockedAgents['a9'] = waitingQuestion('a9');
      app.agentUnread.mark('m', 'a9', AlertKind.needsYou);
      await mount(tester, app, nativeTabs: true);
      await tester.pumpAndSettle();
      List<Map> rows() =>
          (updates.last['statusMenuEntries'] as List).cast<Map>();
      Future<void> select(String method, Map args) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) => done.complete(),
        );
        // Native focus handoff replies after the destination's next frame.
        for (var i = 0; i < 8 && !done.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(done.isCompleted, isTrue);
      }

      expect(
        find.byKey(const ValueKey('workspace-notifications-button')),
        findsNothing,
      );
      expect(rows(), hasLength(2));
      expect(updates.last['unread'], rows().length);
      final stale = rows().singleWhere((r) => r['agentId'] == 'a8');
      app.agentUnread.mark('m', 'a8', AlertKind.failed, fresh: true);
      await tester.pump();
      await select('openStatusHarness', stale);
      expect(app.activeSwarmId, originalTab);
      expect(app.agentUnread.kindFor('m', 'a8'), AlertKind.failed);

      await select(
        'openStatusHarness',
        rows().singleWhere((r) => r['agentId'] == 'a8'),
      );
      expect(app.activeSwarmId, resultTab);
      expect(app.focusedPane, same(result));
      expect(app.allPanes.where((p) => p.agentId == 'a8'), hasLength(1));
      expect(app.agentUnread.kindFor('m', 'a8'), isNull);
      expect(rows().single['agentId'], 'a9');
      expect(updates.last['unread'], 1);
      expect(
        windowActions,
        containsAllInOrder(['isMinimized', 'restore', 'show', 'focus']),
      );

      final displayed = rows();
      app.agentUnread.mark('m', 'a7', AlertKind.done);
      await tester.pump();
      await select('clearStatusNotifications', {'receipts': displayed});
      expect(app.questionFor('m', 'a9'), isNotNull);
      expect(app.questionNotificationRead('m', 'a9'), isTrue);
      expect(notificationInbox(app).single.agentId, 'a7');
      expect(rows().single['agentId'], 'a7');
      expect(app.focusedPane, same(result), reason: 'clearing never navigates');
      await select('clearStatusNotifications', {'receipts': rows()});
      expect(rows(), isEmpty);
      expect(updates.last['unread'], 0);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(const SizedBox());
      expect(updates.last['enabled'], isFalse);
      expect(updates.last['statusMenuEntries'], isNull);
      app.dispose();
    },
  );
}
