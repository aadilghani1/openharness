import 'dart:convert';
import 'dart:isolate';

import 'models.dart';
import 'snapshot_store.dart';

/// One machine as [MachineCache._parseDocument] reads it: what the launch uses, and its agents as the
/// daemon sent them, for the next save.
typedef _ParsedMachine = ({
  CachedMachine cached,
  List<Map<String, dynamic>> rawAgents,
});

/// The machines this account had at the end of the last run, so the next launch
/// can start dialling before `/api/machines` answers.
///
/// ⚠️ **A hint, never a source of truth.** The real list always arrives and
/// always wins: this exists only to fill the ~700ms round-trip during which the
/// app used to know nothing at all and could therefore do nothing at all. A
/// machine in here that the account no longer has is dropped the moment the
/// fetch lands, and one that was added on another device appears then too.
///
/// Only machines the account reported as UP are kept. A machine that was off
/// last time is the one case where acting on stale information costs something
/// real — a dial that opens a relay socket and then waits out its timeout
/// against a computer that is not there — and it is also the case the cache can
/// be most wrong about, because a machine's power state is exactly what changes
/// between two launches. Writing only the live ones means a wrong guess is the
/// cheap direction: at worst the phone waits for the fetch, which is what it did
/// before this existed.
///
/// It also remembers each machine's AGENTS, so the phone can draw its terminal —
/// with the right agent's name on it — while `agents_list` is still in flight.
/// The agents are kept exactly as the daemon sent them, so [Agent.fromJson] is
/// the only thing that ever parses that shape; a hand-written mirror of it would
/// drift the first time a field moved.
///
/// Stored beside the state file rather than in it ([SnapshotStore]): this is a
/// disposable cache with no secrets in it, and it must never take a turn in the
/// lock queue that the session token and the E2EE keys are waiting in.
class CachedMachine {
  const CachedMachine({
    required this.machine,
    required this.agents,
    required this.capabilities,
  });

  final Machine machine;

  /// What this machine last listed. Empty where the last run never got that far,
  /// which is simply a machine whose agents this launch waits for as before.
  final List<Agent> agents;

  /// The machine's last `terminal_capabilities` reply, or null where the last
  /// run never got one — see [MachineCache.rememberCapabilities].
  final Map<String, dynamic>? capabilities;
}

class MachineCache {
  MachineCache({SnapshotStore? store})
    : _store = store ?? FileSnapshotStore('machines-cache');

  final SnapshotStore _store;

  /// The last agent list seen for each machine, as the daemon sent it, awaiting
  /// the next [save].
  ///
  /// Held in memory rather than written on the spot: agent lists arrive one
  /// machine at a time, seconds apart, and a write per arrival would be several
  /// launches' worth of disk churn for a file only the NEXT launch reads. They
  /// go out with the machine list, which is written once per refresh.
  final Map<String, List<Map<String, dynamic>>> _agents = {};

  /// Writes run one at a time, in the order they were asked for.
  ///
  /// ⚠️ **[save] and [clear] race otherwise, and the loser is the file.** Both
  /// are started with `unawaited` — neither is worth making a person wait on —
  /// so a sign-out issued while a refresh's save is still in flight could leave
  /// that save landing AFTER the clear, and the next launch would warm-start
  /// into the machines of the account that just signed out. Queued, the last
  /// call asked for is the last one written.
  Future<void> _writes = Future.value();

  /// Bumped when the shape below changes. An older or newer document reads as no
  /// cache at all, which is always safe — the fetch fills it in.
  static const _version = 1;

  /// What the last run saw, or empty when there is nothing usable — [readRaw], then [parse].
  ///
  /// Never throws: a cache that cannot be read is a cache that is not there.
  Future<List<CachedMachine>> read() async {
    final raw = await readRaw();
    return raw == null ? const [] : parse(raw);
  }

  /// The cache file's text, unparsed — or null when there is none.
  ///
  /// Its own step so a launch can act on the text before paying for the parse: the machine to dial
  /// first is known from the last-opened record, and the text says whether this account still had it
  /// (`AppNotifier._warmStartMachines`). Never throws.
  Future<String?> readRaw() async {
    try {
      final raw = await _store.read();
      return raw == null || raw.isEmpty ? null : raw;
    } on Object {
      return null;
    }
  }

  /// Below this many characters [parse] stays on the calling isolate: spawning one costs more than
  /// a small document does to parse.
  static const _parseOffThreadFrom = 64 * 1024;

  /// [raw] as the machines it lists. Never throws.
  ///
  /// ⚠️ **Parsed off the UI isolate once the file is large (owner, 2026-10-01).** Every agent of
  /// every machine is in here, verbatim, and the whole of it was decoded and turned into [Agent]s
  /// on the thread drawing the launch: measured at 273ms for 103 agents and 629ms for 131, during
  /// which the first frame and the dial both waited. The account the phone is built for has seven
  /// or eight machines of ten to twenty sessions each, which is worse again. Parsed in a background
  /// isolate, the work still takes as long, but nothing on screen waits for it; a small file is
  /// parsed in place, as before, since an isolate's start-up would cost more than it saves.
  Future<List<CachedMachine>> parse(String raw) async {
    List<_ParsedMachine> parsed;
    if (raw.length < _parseOffThreadFrom) {
      parsed = _parseDocument(raw);
    } else {
      try {
        parsed = await Isolate.run(() => _parseDocument(raw));
      } on Object {
        // An isolate that would not start is a parse done here instead, never a cache lost.
        parsed = _parseDocument(raw);
      }
    }
    // Kept for the next [save], on this isolate — see [_agents] and [_capabilities].
    for (final entry in parsed) {
      final machineId = entry.cached.machine.machineId;
      _agents[machineId] = entry.rawAgents;
      // Carried forward so a launch that reads the cache and is closed
      // before any machine answers still writes back what it knew.
      final capabilities = entry.cached.capabilities;
      if (capabilities != null) _capabilities[machineId] = capabilities;
    }
    return [for (final entry in parsed) entry.cached];
  }

  /// The document in [raw], parsed — pure, so it can run on any isolate ([parse]). Empty for a
  /// document that is not this version's, or not one at all.
  static List<_ParsedMachine> _parseDocument(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      if (decoded['version'] != _version) return const [];
      final machines = decoded['machines'];
      if (machines is! List) return const [];
      final parsed = <_ParsedMachine>[];
      for (final item in machines) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final machine = Machine.fromJson(item);
          final rawAgents = item['agents'];
          final agents = <Agent>[];
          if (rawAgents is List) {
            for (final entry in rawAgents) {
              if (entry is! Map<String, dynamic>) continue;
              try {
                agents.add(Agent.fromJson(entry));
              } on Object {
                // One unreadable agent is one agent this launch draws a second
                // later than it might have. Its machine still opens.
                continue;
              }
            }
          }
          final rawCaps = item['capabilities'];
          final capabilities = rawCaps is Map<String, dynamic> ? rawCaps : null;
          parsed.add((
            cached: CachedMachine(
              machine: machine,
              agents: agents,
              capabilities: capabilities,
            ),
            rawAgents: [
              for (final entry in (rawAgents is List ? rawAgents : const []))
                if (entry is Map<String, dynamic>) entry,
            ],
          ));
        } on Object {
          // One malformed entry does not discard the rest; the fetch will
          // correct whatever this cache got wrong either way.
          continue;
        }
      }
      return parsed;
    } on Object {
      return const [];
    }
  }

  /// Remember [agents] — the daemon's own JSON — as this machine's list.
  ///
  /// Kept until the next [save] writes it out. Passing an empty list is
  /// meaningful and is kept: a machine whose agents were all deleted should come
  /// back empty next launch, not with the ones it had before.
  void rememberAgents(String machineId, List<Map<String, dynamic>> agents) =>
      _agents[machineId] = agents;

  /// Remember a machine's `terminal_capabilities` reply, as the daemon sent it.
  ///
  /// ⚠️ **Only ever called with a reply that said the terminal IS available.**
  /// The point of keeping this is to let the next launch attach a terminal
  /// before the negotiation round-trip returns, and a remembered "unavailable"
  /// would instead make the next launch refuse to attach to a machine that may
  /// well be fine by then — a cache that can only do harm. A machine whose tmux
  /// really has gone simply negotiates as it always did, one round-trip in.
  void rememberCapabilities(String machineId, Map<String, dynamic> reply) =>
      _capabilities[machineId] = reply;

  /// See [rememberCapabilities]. Same lifetime as [_agents].
  final Map<String, Map<String, dynamic>> _capabilities = {};

  /// Replace the cache with the machines from a fetch that has just landed.
  ///
  /// Never throws and is never worth awaiting on a path a person is waiting on:
  /// a cache that failed to save costs the NEXT launch a few hundred
  /// milliseconds and costs this one nothing.
  Future<void> save(
    Iterable<Machine> machines, {
    required bool Function(Machine) isOnline,
  }) {
    // Encoded now, on the caller's turn, so the document written is the machine
    // list as it was when the save was ASKED for rather than whatever the list
    // has become by the time the queue reaches it.
    final payload = jsonEncode({
      'version': _version,
      'machines': [
        for (final machine in machines.where(isOnline))
          {
            'machineId': machine.machineId,
            'computerId': machine.computerId,
            'authMode': machine.authMode.name,
            'engine': machine.engine,
            'name': machine.name,
            'hostname': machine.hostname,
            // Written as the status that got it in here. The reader treats
            // every cached machine as a candidate to dial, and the fetch
            // replaces this with the truth within the second.
            'status': machine.status,
            // The daemon's own agent JSON, verbatim — see the class comment.
            // Absent where this run never listed that machine's agents, which
            // reads back as a machine with no cached agents.
            'agents': ?_agents[machine.machineId],
            'capabilities': ?_capabilities[machine.machineId],
          },
      ],
    });
    return _queue(() => _store.write(payload));
  }

  /// Forget everything — what signing out does, so the next account does not
  /// start by dialling the previous one's machines.
  Future<void> clear() {
    _agents.clear();
    _capabilities.clear();
    return _queue(_store.clear);
  }

  /// Run [write] after every write already asked for, swallowing its failure.
  Future<void> _queue(Future<void> Function() write) {
    final queued = _writes.then((_) async {
      try {
        await write();
      } on Object {
        // Best effort, exactly like the snapshot store's own contract: a cache
        // that failed to save costs the next launch a few hundred milliseconds.
      }
    });
    _writes = queued;
    return queued;
  }
}
