import 'dart:async';
import 'dart:convert';

import 'package:harness/companions/coding_memory_connection.dart';

Map<String, dynamic> syntheticMemory({
  int revision = 1,
  String? claim,
  bool project = false,
}) => {
  'id': 'synthetic-memory',
  'revision': revision,
  'state': 'active',
  'scope': {
    'profileId': 'synthetic-owner',
    if (project) 'projectId': 'synthetic-project',
  },
  'kind': 'working_preference',
  'facet': 'testing',
  'assertionType': 'stated_preference',
  'claim': claim ?? 'For regression fixes, start with a small failing test.',
  'rationale': 'It makes the failure and the fix easier to review.',
  'futureAction': 'Reproduce the bug with a focused test before changing the implementation.',
  'evidenceClass': 'user_stated',
  'applicability': {'task': 'bug_fix'},
  'exceptions': [],
  'retrievalCues': ['regression', 'testing'],
  'validity': {'validFrom': null, 'validUntil': null, 'recheckWhen': []},
  'createdAt': 1790762400000,
  'updatedAt': 1790762400000,
  'evidence': [
    {
      'sourceEventId': 'source-fixture',
      'quote': 'When fixing a bug, write a small failing test first.',
      'paths': ['/claim', '/futureAction'],
    },
  ],
};

class MemoryFixture extends CodingMemoryConnection {
  @override
  bool valid = true;
  @override
  int epoch = 0;
  final calls = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? handle;
  Map<String, dynamic> record = syntheticMemory();
  bool learn = true, recall = true, present = true;
  String? cursor;
  String? refuseApply;
  Map<String, dynamic>? previewed;
  final projects = <Map<String, dynamic>>[
    {
      'id': 'synthetic-project',
      'name': 'editor',
      'location': '/synthetic/work/editor',
    },
    {
      'id': 'second-project',
      'name': 'editor',
      'location': '/synthetic/research/editor',
    },
  ];
  final scopeChanges = <Map<String, dynamic>>[];

  Map<String, dynamic>? get project => projects
      .where((p) => p['id'] == (record['scope'] as Map)['projectId'])
      .firstOrNull;

  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> payload) async {
    calls.add(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(payload)) as Map),
    );
    if (handle != null) return handle!(payload);
    return respond(payload);
  }

  Map<String, dynamic> respond(Map<String, dynamic> payload) {
    switch (payload['action']) {
      case 'status':
        return {
          'ok': true,
          'runtime': {'state': 'ready'},
          'preferences': {'learn': learn, 'recall': recall},
          'queue': {
            'jobs': {'queued': 2, 'reviewing': 1, 'budget_deferred': 1},
            'retention': {'expiredEpisodes': 1},
          },
        };
      case 'list':
        return {
          'ok': true,
          'items': present ? [record] : [],
          'nextCursor': cursor,
          'version': {
            'generation': 1,
            'knowledge': record['revision'],
            'preferences': '$learn:$recall',
          },
        };
      case 'show':
        return present
            ? {
                'ok': true,
                'record': record,
                'support': null,
                'project': project,
                'scopeChanges': scopeChanges,
                'sources': [
                  {
                    'id': 'source-fixture',
                    'engine': 'claude',
                    'sessionId': 'fixture-session',
                    'role': 'user',
                    'observedAt': 1790762400000,
                  },
                ],
              }
            : {'ok': false, 'error': 'NOT_FOUND'};
      case 'projects':
        final query = payload['query'] as Map;
        final search = (query['search'] as String).toLowerCase();
        return {
          'ok': true,
          'items': projects
              .where(
                (p) => '${p['name']} ${p['location']}'.toLowerCase().contains(
                  search,
                ),
              )
              .toList(),
          'nextBefore': null,
        };
      case 'preview':
        previewed = payload['command'] as Map<String, dynamic>;
        return {
          'ok': true,
          'capability': 'a' * 32,
          'expiresInMs': 120000,
          'preview': {
            'command': previewed,
            'version': {
              'generation': 1,
              'knowledge': 1,
              'preferences': 'fixture',
            },
            'effects': previewed!['kind'] == 'forget'
                ? {
                    'deletedIds': [record['id'], 'dependent'],
                    'deletedTopicIds': ['topic'],
                    'alreadyDeliveredContent': 'not_erased',
                  }
                : previewed!['kind'] == 'configure'
                ? {'preferences': previewed!['preferences']}
                : previewed!['kind'] == 'narrow'
                ? {
                    'record': {
                      ...record,
                      'scope': {
                        ...record['scope'] as Map,
                        'projectId': previewed!['projectId'],
                      },
                    },
                    'project': projects.singleWhere(
                      (p) => p['id'] == previewed!['projectId'],
                    ),
                  }
                : {
                    'record': {...record, ...previewed!['fields'] as Map},
                  },
          },
        };
      case 'apply':
        if (refuseApply != null) return {'ok': false, 'error': refuseApply};
        if (previewed!['kind'] == 'configure') {
          final prefs = previewed!['preferences'] as Map;
          learn = prefs['learn'] as bool;
          recall = prefs['recall'] as bool;
        } else if (previewed!['kind'] == 'forget') {
          present = false;
        } else if (previewed!['kind'] == 'narrow') {
          final from = record['scope'];
          record = {
            ...record,
            'scope': {...from as Map, 'projectId': previewed!['projectId']},
            'revision': (record['revision'] as int) + 1,
          };
          scopeChanges.add({
            'revision': record['revision'],
            'from': from,
            'to': record['scope'],
            'changedAt': 1790762400000,
            'actor': 'owner',
          });
        } else {
          record = {
            ...record,
            ...previewed!['fields'] as Map,
            'revision': (record['revision'] as int) + 1,
          };
        }
        return {'ok': true};
      default:
        throw StateError('Unexpected fixture action');
    }
  }

  void reconnect() {
    ++epoch;
    notifyListeners();
  }

  @override
  void invalidate() {
    valid = false;
    ++epoch;
    notifyListeners();
  }
}
