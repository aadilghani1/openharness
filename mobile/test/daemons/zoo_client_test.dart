// The phone's zoo client against an in-memory backend: the first read is a
// baseline, `zoo_changed` only fetches news, the phone's own writes show at
// once and survive a failed send, a hatch answers who came out, and a sign-out
// drops everything in flight.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/daemons/zoo_client.dart';
import 'package:harness_mobile/state/app_state.dart';

import '../agent_pager_fixture.dart';
import 'zoo_fixture.dart';

void main() {
  late FakeZooBackend backend;
  late ZooClient client;
  late List<ZooEvent> events;

  setUp(() {
    backend = FakeZooBackend();
    client = ZooClient(read: backend.read, write: backend.write);
    events = [];
    client.events.listen(events.add);
  });
  tearDown(() => client.dispose());

  Future<void> join() async {
    client.ensure();
    await pumpEventQueue();
  }

  test('nothing is shown until the first read, which is a baseline', () async {
    expect(client.loaded, isFalse);
    expect(client.paired, isNull);
    await join();
    expect(client.loaded, isTrue);
    expect(client.revision, 3);
    expect(client.paired!.id, 'tim');
    expect(client.readyEgg!.id, 'e1');
    expect(client.zoo.ownedIds, ['tim', 'vim']);
    expect(events, isEmpty);
  });

  test('zoo_changed only fetches a revision the phone has not seen', () async {
    await join();
    final reads = backend.reads;
    // Once per connected machine, at the same revision.
    client.noticeRevision(3);
    client.noticeRevision(3);
    await pumpEventQueue();
    expect(backend.reads, reads);

    backend.revision = 4;
    backend.zoo['eggs'] = [
      ...backend.zoo['eggs'] as List,
      {'id': 'e2', 'kind': 'week', 'grantedAt': '2026-09-29T00:00:00Z'},
    ];
    (backend.zoo['daemons'] as List)[0] = {
      'id': 'tim',
      'hatchedAt': '2026-09-26T09:42:00Z',
      'egg': 'first',
      'xp': 160,
    };
    client.noticeRevision(4);
    client.noticeRevision(4);
    await pumpEventQueue();
    expect(backend.reads, reads + 1);
    expect(client.zoo.eggs.map((e) => e.id), ['e1', 'e2']);
    expect(client.paired!.version, '1.0');
    expect(events.whereType<ZooEggArrived>().single.egg.kind, 'week');
    final grew = events.whereType<ZooDaemonGrew>().single;
    expect(grew.daemon.id, 'tim');
    expect(grew.versionChanged, isTrue);
  });

  test('a pair switch shows at once and is sent once', () async {
    await join();
    client.pair('vim');
    expect(client.paired!.id, 'vim');
    await client.settle();
    expect(backend.written, [
      {'op': 'zoo.pair', 'id': 'vim'},
    ]);
    // Pairing what is already paired, or what is not owned, sends nothing.
    client.pair('vim');
    client.pair('grue');
    await client.settle();
    expect(backend.written, hasLength(1));
  });

  test(
    'a write that failed is kept, shown, and sent with the next read',
    () async {
      await join();
      backend.failWrites = true;
      client.habit('elsewhere');
      await client.settle();
      expect(backend.written, isEmpty);
      expect(client.zoo.habits, contains('elsewhere'));

      // A read in between does not undo it.
      backend.failWrites = false;
      await client.refresh();
      await client.settle();
      expect(client.zoo.habits, contains('elsewhere'));
      expect(backend.written, [
        {'op': 'zoo.habit', 'key': 'elsewhere'},
      ]);
      // A habit already recorded is not sent again.
      client.habit('elsewhere');
      client.habit('turn');
      client.habit('not-a-habit');
      await client.settle();
      expect(backend.written, hasLength(1));
    },
  );

  test('hatching answers who came out, and the zoo follows', () async {
    await join();
    final future = client.hatch('e1');
    expect(client.hatchingEgg, 'e1');
    // One hatch at a time.
    expect(await client.hatch('e1'), isNull);
    final hatch = await future;
    expect(hatch!.daemonId, 'fzf');
    expect(hatch.shiny, isTrue);
    expect(client.hatchingEgg, isNull);
    expect(client.zoo.eggs, isEmpty);
    expect(client.zoo.ownedIds, ['tim', 'vim', 'fzf']);
    // An egg that is gone opens nothing.
    expect(await client.hatch('e1'), isNull);
  });

  test(
    'a hatch the backend cannot answer leaves the egg in the nest',
    () async {
      await join();
      backend.failWrites = true;
      expect(await client.hatch('e1'), isNull);
      expect(client.readyEgg!.id, 'e1');
      expect(client.hatchingEgg, isNull);
    },
  );

  test('a sign-out drops what is in flight', () async {
    await join();
    backend.holdWrites = Completer<void>();
    final future = client.hatch('e1');
    client.reset();
    expect(client.loaded, isFalse);
    expect(client.zoo.daemons, isEmpty);
    backend.holdWrites!.complete();
    expect(await future, isNull);
    expect(client.loaded, isFalse);
  });

  test('a backend without a zoo leaves the phone without a daemon', () async {
    final none = ZooClient(read: () async => null, write: (_) async => null);
    addTearDown(none.dispose);
    none.ensure();
    await pumpEventQueue();
    expect(none.loaded, isFalse);
  });

  test('the app reads the zoo on zoo_changed and on resume', () async {
    final app = pagerApp(PagerConn());
    addTearDown(app.dispose);
    app.api = ZooApi(backend);
    app.zoo.ensure();
    await pumpEventQueue();
    expect(app.zoo.paired!.id, 'tim');

    backend.zoo['pair'] = 'vim';
    backend.revision = 9;
    await app.handleEventForTest('m', {
      'type': 'zoo_changed',
      'payload': {'revision': 9},
    });
    await pumpEventQueue();
    expect(app.zoo.paired!.id, 'vim');
    expect(app.zoo.revision, 9);

    // Back from a pocket: whatever was pushed while suspended is read now.
    backend.zoo['pair'] = 'tim';
    backend.revision = 10;
    app.status = AppStatus.authenticated;
    app.handleAppResumed();
    await pumpEventQueue();
    expect(app.zoo.paired!.id, 'tim');
  });
}
