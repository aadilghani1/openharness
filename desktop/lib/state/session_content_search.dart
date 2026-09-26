import 'dart:async';

import 'package:flutter/foundation.dart';

import 'swarm_navigation.dart' show agentDestinationId;

/// Where a machine's daemon marks each matched word in a snippet.
const kSnippetMarkOpen = '\u0002';
const kSnippetMarkClose = '\u0003';

/// One conversation that matched a search, as its machine's daemon found it
/// (`session_search`, cli/src/lib/sessionSearch/). The daemon has read every
/// turn of every session on that machine; the app only ever sees the hits.
@immutable
class SessionContentHit {
  const SessionContentHit({
    required this.machineId,
    required this.agentId,
    required this.sessionId,
    required this.field,
    required this.snippet,
    required this.together,
    required this.score,
    this.turn = 0,
    this.at,
  });

  final String machineId, agentId, sessionId;

  /// `ask`, `answer`, `tools` or `name`: which part of the turn matched.
  final String field;

  /// The words around the match, each matched word between
  /// [kSnippetMarkOpen] and [kSnippetMarkClose].
  final String snippet;

  /// Every searched word in one turn, rather than spread across the session.
  final bool together;

  /// 0–1, higher is better: relevance blended with recency by the daemon.
  final double score;
  final int turn;

  /// When the matching turn happened, when the transcript says.
  final DateTime? at;

  String get destinationId => agentDestinationId(machineId, agentId);

  /// The snippet as plain text, marks removed.
  String get plainSnippet => snippet
      .replaceAll(kSnippetMarkOpen, '')
      .replaceAll(kSnippetMarkClose, '');

  static SessionContentHit? fromJson(String machineId, Object? raw) {
    if (raw is! Map) return null;
    final agentId = raw['agentId'];
    final sessionId = raw['sessionId'];
    final snippet = raw['snippet'];
    if (agentId is! String || agentId.isEmpty || sessionId is! String) {
      return null;
    }
    final score = raw['score'];
    final at = raw['at'];
    final turn = raw['turn'];
    return SessionContentHit(
      machineId: machineId,
      agentId: agentId,
      sessionId: sessionId,
      field: raw['field'] is String ? raw['field'] as String : 'ask',
      snippet: snippet is String
          ? snippet.length > 600
                ? snippet.substring(0, 600)
                : snippet
          : '',
      together: raw['together'] == true,
      score: score is num ? score.toDouble().clamp(0, 1) : 0,
      turn: turn is int ? turn : 0,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }

  /// A `session_search_result` payload, or an empty list for an error.
  static List<SessionContentHit> listFromReply(
    String machineId,
    Map<String, dynamic> reply,
  ) {
    final hits = reply['hits'];
    if (reply['error'] != null || hits is! List) return const [];
    return [
      for (final raw in hits.take(100))
        ?SessionContentHit.fromJson(machineId, raw),
    ];
  }
}

typedef SessionSearchAsk = Future<List<SessionContentHit>?> Function(
  String machineId,
  String query,
);

/// Asks every reachable machine what was said in its sessions, as the person
/// types in Cmd-P. Debounced so a burst of keys is one question; an answer to
/// an older question is dropped. Hits are keyed by the harness row they belong
/// to, and a machine that cannot answer (offline, or a CLI that predates
/// `session_search`) simply adds none.
class SessionContentSearch extends ChangeNotifier {
  SessionContentSearch({
    required this.machines,
    required this.ask,
    this.debounce = const Duration(milliseconds: 110),
  });

  /// The machines to ask right now.
  final Iterable<String> Function() machines;
  final SessionSearchAsk ask;
  final Duration debounce;

  Map<String, SessionContentHit> _hits = const {};
  Map<String, SessionContentHit> get hits => _hits;

  /// The query the current [hits] answer, or null while none have arrived.
  String? get answered => _answered;
  String? _answered;

  String _query = '';
  int _generation = 0;
  Timer? _timer;
  bool _disposed = false;

  /// Two letters at least: one matches too much of everything to mean anything.
  static bool searchable(String query) => query.trim().runes.length >= 2;

  void search(String query) {
    final next = query.trim();
    if (next == _query) return;
    final previous = _query;
    _query = next;
    _timer?.cancel();
    final generation = ++_generation;
    // Typing more of the same words keeps the last answer on screen until the
    // new one lands; anything else would show rows for words no longer typed.
    if (!next.toLowerCase().startsWith(previous.toLowerCase()) ||
        !searchable(next)) {
      if (_hits.isNotEmpty || _answered != null) {
        _hits = const {};
        _answered = null;
        notifyListeners();
      }
    }
    // Nothing to ask while every machine is offline: no timer, no work.
    if (!searchable(next) || machines().isEmpty) return;
    _timer = Timer(debounce, () => _run(next, generation));
  }

  Future<void> _run(String query, int generation) async {
    final found = <String, SessionContentHit>{};
    var first = true;
    await Future.wait([
      for (final machineId in machines())
        ask(machineId, query).then((hits) {
          if (_disposed || generation != _generation) return;
          if (first) {
            // The first answer replaces what an earlier question found.
            first = false;
            _hits = const {};
          }
          for (final hit in hits ?? const <SessionContentHit>[]) {
            final id = hit.destinationId;
            final known = found[id];
            // One row per harness: its best conversation, earlier ones included.
            if (known == null ||
                (hit.together && !known.together) ||
                (hit.together == known.together && hit.score > known.score)) {
              found[id] = hit;
            }
          }
          _hits = Map.unmodifiable(found);
          _answered = query;
          notifyListeners();
        }, onError: (_) {}),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
