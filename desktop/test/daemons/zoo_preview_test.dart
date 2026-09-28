import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/daemons/daemon_settings.dart';
import 'package:harness/daemons/zoo_controller.dart';

import 'zoo_test.dart' show FakeZooTransport;

class _NoStorage implements LocalKeyValueStore {
  final calls = <String>[];
  @override
  Future<String?> read(String key) async {
    calls.add('read:$key');
    return null;
  }

  @override
  Future<void> write(String key, String value) async => calls.add('write:$key');
  @override
  Future<void> delete(String key) async => calls.add('delete:$key');
}

void main() {
  test('preview hatches, names, pairs and earns only in memory', () async {
    final storage = _NoStorage();
    final zoo = ZooController(
      storage: storage,
      random: Random(7),
      now: () => DateTime.utc(2026, 9, 28),
    );
    addTearDown(zoo.dispose);
    zoo.showPreview();
    expect(zoo.source, ZooSource.preview);
    expect(zoo.paired!.id, 'tim');
    expect(zoo.needsHint, isFalse);
    final hatch = (await zoo.hatch(zoo.readyEgg!.id))!;
    expect(zoo.nickname(hatch.uid!, 'Pip'), isTrue);
    zoo.pair(hatch.uid!);
    zoo.recordTurns(3, machineId: 'fixture');
    zoo.noteDay();
    zoo.habit('split');
    await zoo.flush();
    expect(zoo.paired!.name, 'Pip');
    expect(zoo.paired!.xp, greaterThan(0));
    expect(storage.calls, isEmpty);

    zoo.bind(null);
    expect(zoo.loaded, isFalse);
    zoo.showPreview();
    expect(
      zoo.paired!.name,
      'Pip',
      reason: 'hide/show keeps this window’s zoo',
    );
    final another = ZooController(storage: storage);
    addTearDown(another.dispose);
    another.showPreview();
    expect(another.zoo.daemons, hasLength(1));
    expect(another.paired!.id, 'tim', reason: 'a new window starts fresh');

    // Switching to a real account can never upload the preview as a guest seed.
    final remote = FakeZooTransport();
    zoo.bind('account:test', remote: remote);
    await Future<void>.delayed(Duration.zero);
    await zoo.flush();
    expect(zoo.isAccount, isTrue);
    expect(zoo.zoo.daemons, isEmpty);
    expect(remote.batches, isEmpty);
    expect(storage.calls.where((c) => c.startsWith('write:')), isEmpty);
  });

  test('a late account reply cannot replace the preview', () async {
    final gate = Completer<void>();
    final remote = FakeZooTransport()..gate = gate;
    final zoo = ZooController();
    addTearDown(zoo.dispose);
    zoo.bind('account:test', remote: remote);
    zoo.showPreview();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    zoo.refresh();
    zoo.pushed(999);
    expect(zoo.isPreview, isTrue);
    expect(zoo.paired!.uid, 'preview-tim');
    expect(remote.fetches, 1);
    expect(remote.batches, isEmpty);
  });

  test(
    'preview motion and quiet preferences do not touch saved settings',
    () async {
      final storage = _NoStorage();
      final settings = DaemonSettings(
        storage: storage,
        canPersist: () => false,
      );
      addTearDown(settings.dispose);
      await settings.load();
      settings.motion = false;
      settings.quiet = true;
      settings.tab = 'zoo';
      await settings.flush();
      expect(storage.calls, isEmpty);
      expect(settings.motion, isFalse);
      expect(settings.quiet, isTrue);
    },
  );
}
