// The backend's zoo routes, answered in memory, for the phone's daemon tests.
import 'dart:async';

import 'package:harness_mobile/api/api_client.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';

/// `routes/zoo.ts`, answered in memory. Hatches always give [nextDaemon].
class FakeZooBackend {
  int revision = 3;
  Map<String, dynamic> zoo = {
    'daemons': [
      {
        'id': 'tim',
        'hatchedAt': '2026-09-26T09:42:00Z',
        'egg': 'first',
        'xp': 0,
      },
      {
        'id': 'vim',
        'hatchedAt': '2026-09-27T09:42:00Z',
        'egg': 'turn',
        'xp': 0,
      },
    ],
    'eggs': [
      {'id': 'e1', 'kind': 'turn', 'grantedAt': '2026-09-28T00:00:00Z'},
    ],
    'pair': 'tim',
    'habits': ['turn', 'split'],
    'firstEgg': true,
  };
  String nextDaemon = 'fzf';
  int reads = 0;
  final written = <Map<String, dynamic>>[];
  bool failWrites = false;
  Completer<void>? holdWrites;

  Map<String, dynamic> get doc => {'revision': revision, 'zoo': zoo};

  Future<Map<String, dynamic>?> read() async {
    reads++;
    return doc;
  }

  Future<Map<String, dynamic>?> write(List<Map<String, dynamic>> ops) async {
    await holdWrites?.future;
    if (failWrites) throw Exception('offline');
    written.addAll(ops);
    final hatched = <Map<String, dynamic>>[];
    for (final op in ops) {
      switch (op['op']) {
        case 'zoo.habit':
          zoo['habits'] = [...zoo['habits'] as List, op['key']];
        case 'zoo.pair':
          zoo['pair'] = op['id'];
        case 'zoo.hatch':
          zoo['eggs'] = [
            for (final e in zoo['eggs'] as List)
              if ((e as Map)['id'] != op['eggId']) e,
          ];
          zoo['daemons'] = [
            ...zoo['daemons'] as List,
            {
              'id': nextDaemon,
              'hatchedAt': '2026-09-28T10:00:00Z',
              'egg': 'turn',
            },
          ];
          hatched.add({
            'eggId': op['eggId'],
            'daemonId': nextDaemon,
            'shiny': true,
          });
      }
    }
    revision++;
    return {...doc, 'hatched': hatched, 'grants': [], 'levelUps': []};
  }
}

/// The real [ApiClient] with the zoo routes answered by [backend].
class ZooApi extends ApiClient {
  ZooApi(this.backend) : super(config: AppConfig.dev, session: AuthSession());
  final FakeZooBackend backend;
  @override
  Future<Map<String, dynamic>?> zoo() => backend.read();
  @override
  Future<Map<String, dynamic>?> zooOps(List<Map<String, dynamic>> ops) =>
      backend.write(ops);
  // No desk on this backend: the phone then swipes the whole account.
  @override
  Future<Map<String, dynamic>?> desk() async => null;
}
