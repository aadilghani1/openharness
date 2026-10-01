import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/snapshot_store.dart';
import '../terminal/screen_snapshot.dart';

/// The last screens of the agents opened most recently, kept on the phone so the next open — in
/// this run or the next — shows one at once instead of a skeleton while the stream attaches.
///
/// ⚠️ **Why the phone keeps terminal screens at all (owner, 2026-10-01).** A launch spends 2–3s
/// reaching the machine before the first keyframe of the agent it reopens can arrive, and that
/// floor is the network's: the relay dial, the E2EE handshake, the machine's answer. What the person
/// sees in those seconds is the only part of it the phone decides. With the screen they left on
/// disk, the agent is on screen in the first frames of the launch — stale by however long the app
/// was closed, which the page's "Attaching…" says — and the live keyframe replaces it whole.
///
/// What it costs, and how it is bounded:
///  - **A terminal's contents on the phone's disk.** Only the visible screen ([ScreenSnapshot]),
///    only the last [capacity] agents and none older than [maxAge], in the app's CACHE directory —
///    which iOS leaves out of iCloud backups and Android out of Auto Backup, and either may empty
///    when space runs low, which costs nothing but a skeleton — and forgotten on sign-out ([clear]).
///  - **Disk writes.** Batched ([_saveDelay]) and only when something changed; [flush] writes at
///    once when the app goes to the background, where a closed app would otherwise lose them.
class KeptScreenStore {
  KeptScreenStore({SnapshotStore? store, DateTime Function()? now})
    : _store = store ?? _defaultStore(),
      _now = now ?? DateTime.now;

  final SnapshotStore _store;
  final DateTime Function() _now;

  /// How many agents' screens are kept: the ones a launch, a swipe or Find is likely to open next.
  /// The least recently kept goes first once there are more (owner, 2026-10-01: fifty — an account
  /// of seven or eight machines at ten to twenty sessions each opens well past the first two dozen).
  /// At a few kilobytes a screen, typically well under a megabyte in all.
  static const capacity = 50;

  /// How old a kept screen may be and still be shown (owner, 2026-10-01). Past it the screen says
  /// too little about the agent now to stand in for it, and is dropped — on read and on load —
  /// rather than kept on the phone for nothing.
  static const maxAge = Duration(days: 7);

  static const _version = 1;
  static const _saveDelay = Duration(seconds: 2);

  /// By key (`machineId/agentId`), least recently kept first — see [put].
  final _screens = <String, ScreenSnapshot>{};

  Future<void>? _loading;
  bool _dirty = false;
  bool _cleared = false;
  Timer? _saveTimer;

  /// Writes run one at a time, in the order asked for — a save and a [clear] racing otherwise
  /// leave whichever finished last, and the clear must win.
  Future<void> _writes = Future.value();

  /// The screen kept for [key], or null — null too for one past [maxAge], which is dropped here.
  ScreenSnapshot? read(String key) {
    final snapshot = _screens[key];
    if (snapshot == null) return null;
    if (_isStale(snapshot)) {
      remove(key);
      return null;
    }
    return snapshot;
  }

  /// Whether [snapshot] is older than [maxAge]. Measured on this phone's clock, which also took it.
  bool _isStale(ScreenSnapshot snapshot) =>
      _now().difference(snapshot.savedAt) > maxAge;

  /// Read the kept screens from disk, once. Screens [put] before it lands are newer and win.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await _store.read();
    if (raw == null || raw.isEmpty || _cleared) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _version) return;
      final screens = decoded['screens'];
      if (screens is! List) return;
      final loaded = <String, ScreenSnapshot>{};
      var dropped = false;
      for (final item in screens) {
        if (item is! Map) continue;
        final key = item['key'];
        final snapshot = ScreenSnapshot.fromJson(item['screen']);
        if (key is! String || key.isEmpty || snapshot == null) continue;
        // Past [maxAge]: left out, and the file rewritten without it below.
        if (_isStale(snapshot)) {
          dropped = true;
          continue;
        }
        loaded.remove(key);
        loaded[key] = snapshot;
      }
      // What was put meanwhile is newer than anything on disk, so it goes after — taken out of
      // [loaded] first, since a key already there would keep its old place in the order.
      final newer = Map.of(_screens);
      loaded.removeWhere((key, _) => newer.containsKey(key));
      _screens
        ..clear()
        ..addAll(loaded)
        ..addAll(newer);
      if (_trim()) dropped = true;
      if (dropped) _changed();
    } on Object {
      // An unreadable file is no kept screens: the next save replaces it.
    }
  }

  /// Keep [snapshot] as [key]'s screen, as the most recent.
  void put(String key, ScreenSnapshot snapshot) {
    _cleared = false;
    _screens.remove(key);
    _screens[key] = snapshot;
    _trim();
    _changed();
  }

  /// Forget [key]'s screen — its agent was deleted, or its screen is past [maxAge].
  void remove(String key) {
    if (_screens.remove(key) == null) return;
    _changed();
  }

  /// Something to write: soon, batched with whatever else changes meanwhile ([_saveDelay]).
  void _changed() {
    _dirty = true;
    _saveTimer ??= Timer(_saveDelay, () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  /// Write what changed, now.
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return _writes;
    _dirty = false;
    final contents = jsonEncode({
      'version': _version,
      'screens': [
        for (final entry in _screens.entries)
          {'key': entry.key, 'screen': entry.value.toJson()},
      ],
    });
    return _writes = _writes.then((_) => _store.write(contents));
  }

  /// Forget every kept screen, in memory and on disk — signing out.
  Future<void> clear() {
    _cleared = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty = false;
    _screens.clear();
    return _writes = _writes.then((_) => _store.clear());
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// Down to [capacity], least recently kept first. Whether anything went.
  bool _trim() {
    var trimmed = false;
    while (_screens.length > capacity) {
      _screens.remove(_screens.keys.first);
      trimmed = true;
    }
    return trimmed;
  }

  /// The real store, in the app's cache directory — see the class note. Resolved without a plugin,
  /// the way `containerHome` is (`core/host_platform.dart`): iOS names `<container>/tmp`, whose
  /// sibling `Library/Caches` is the cache; Android's temporary directory IS its cache directory.
  static SnapshotStore _defaultStore() {
    try {
      final temporary = Directory.systemTemp.path;
      final directory = Platform.isIOS
          ? '${Directory.systemTemp.parent.path}/Library/Caches/harness'
          : '$temporary/harness';
      return FileSnapshotStore('kept-screens', directory: Directory(directory));
    } on Object {
      return MemorySnapshotStore();
    }
  }
}
