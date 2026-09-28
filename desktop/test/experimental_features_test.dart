import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/settings/experimental_features.dart';

import 'swarm_state_test.dart' show MemoryStore;

class _DelayedRead extends MemoryStore implements BatchLocalKeyValueStore {
  final ready = Completer<Map<String, String?>>();

  @override
  Future<Map<String, String?>> readMany(Iterable<String> keys) => ready.future;
}

class _DelayedWrite extends MemoryStore {
  final ready = Completer<void>();
  int writes = 0;
  bool fail = false;

  @override
  Future<void> write(String key, String value) async {
    if (++writes == 1) await ready.future;
    if (fail) throw StateError('synthetic write failure');
    await super.write(key, value);
  }
}

void main() {
  const creature = ExperimentalFeature.focusBarCreature;

  test('experiments default off and restore both saved choices', () async {
    final storage = MemoryStore();
    Future<ExperimentalFeaturesStore> reopen() async {
      final store = ExperimentalFeaturesStore(storage: storage);
      addTearDown(store.dispose);
      await store.load();
      return store;
    }

    final first = await reopen();
    expect(first.enabled(creature), isFalse);
    expect(first.choice(creature), isNull);
    expect(storage.values, isEmpty);
    await first.set(creature, true);
    final second = await reopen();
    expect(second.enabled(creature), isTrue);
    await second.set(creature, false);
    final third = await reopen();
    expect(third.choice(creature), isFalse);
    storage.values[creature.storageKey] = 'true';
    expect((await reopen()).enabled(creature), isFalse);
  });

  test(
    'a late preference read cannot undo a choice made in Settings',
    () async {
      final storage = _DelayedRead();
      final store = ExperimentalFeaturesStore(storage: storage);
      addTearDown(store.dispose);
      final loading = store.load();
      await store.set(creature, true);
      storage.ready.complete({creature.storageKey: 'off'});
      await loading;
      expect(store.enabled(creature), isTrue);
      expect(storage.values[creature.storageKey], 'on');
    },
  );

  test(
    'rapid flips apply immediately and save the final choice last',
    () async {
      final storage = _DelayedWrite();
      final store = ExperimentalFeaturesStore(storage: storage);
      addTearDown(store.dispose);
      final on = store.set(creature, true);
      final off = store.set(creature, false);
      expect(store.enabled(creature), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(storage.writes, 1);
      expect(storage.values, isEmpty);
      storage.ready.complete();
      await Future.wait([on, off]);
      expect(storage.values[creature.storageKey], 'off');
    },
  );

  test(
    'a failed save can be retried without flipping the switch again',
    () async {
      final storage = _DelayedWrite()..fail = true;
      storage.ready.complete();
      final store = ExperimentalFeaturesStore(storage: storage);
      addTearDown(store.dispose);
      await expectLater(store.set(creature, true), throwsStateError);
      expect(store.enabled(creature), isTrue);
      storage.fail = false;
      await store.set(creature, true);
      expect(storage.values[creature.storageKey], 'on');
    },
  );
}
