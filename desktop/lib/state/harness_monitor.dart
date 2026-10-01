import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/harness_resources.dart';
import '../core/models.dart';
import 'app_state.dart';
import 'harness_sessions.dart';

/// A single, demand-driven sampler shared by the footer and its open panel.
/// It never starts an agent, opens a connection, or scans conversation files.
class HarnessMonitor extends ChangeNotifier {
  HarnessMonitor(this.app);
  final AppNotifier app;
  final _samples = <String, (MachineState, MachineHarnessResources)>{};
  Timer? _timer;
  bool _started = false, _disposed = false, _busy = false, _expanded = false;
  int _revision = 0;

  List<HarnessSession> get sessions => harnessSessions(app, includeLive: true);
  List<HarnessSession> get live => sessions
      .where((row) => row.running && !row.machine.machine.isShared)
      .toList();

  HarnessResources? reading(HarnessSession row) {
    final snapshot = _samples[row.machineId];
    return row.running && identical(snapshot?.$1, row.machine)
        ? snapshot?.$2.agents[row.agent.id]
        : null;
  }

  /// Shared-server RSS belongs to the server, not to each conversation.
  /// Count it once per machine/profile and label it separately in the panel.
  List<HarnessResources> get sharedReadings {
    final rows = live;
    return [
      for (final entry in _samples.entries)
        if (identical(app.stateOf(entry.key), entry.value.$1))
          for (final shared in entry.value.$2.shared)
            if (rows.any(
              (row) =>
                  row.machineId == entry.key &&
                  shared.$1.contains(row.agent.id),
            ))
              shared.$2,
    ];
  }

  String? get sharedLabel {
    final rows = sharedReadings;
    if (rows.isEmpty) return null;
    final known = rows.where((r) => r.memoryBytes != null).toList();
    final memory = known.fold<double>(0, (sum, r) => sum + r.memoryBytes!);
    return 'Shared Codex servers · ${formatHarnessMemory(known.isEmpty ? null : memory)}${known.isNotEmpty && known.length < rows.length ? '+' : ''} RAM';
  }

  String get label {
    final rows = live;
    if (rows.isEmpty) return '0 live';
    (double?, bool) sum(double? Function(HarnessResources) value) {
      double total = 0;
      int known = 0;
      for (final row in rows) {
        final sample = reading(row);
        final n = sample == null ? null : value(sample);
        if (n != null) {
          total += n;
          known++;
        }
      }
      final shared = sharedReadings;
      for (final sample in shared) {
        final n = value(sample);
        if (n != null) {
          total += n;
          known++;
        }
      }
      return (
        known == 0 ? null : total,
        known > 0 && known < rows.length + shared.length,
      );
    }

    final memory = sum((r) => r.memoryBytes), cpu = sum((r) => r.cpuPercent);
    return '${rows.length} live · ${formatHarnessMemory(memory.$1)}${memory.$2 ? '+' : ''} · ${cpu.$1 == null ? '—' : cpu.$1!.toStringAsFixed(0)}%${cpu.$2 ? '+' : ''} CPU';
  }

  String get detail =>
      'Harness Monitor — $label\nLive sessions on connected machines. + means some readings are unavailable. ${HarnessResources.explanation}${sharedLabel == null ? '' : '\n$sharedLabel, included once in the total. These servers may also serve sessions outside Harness.'}';

  void start() {
    if (_started || _disposed) return;
    _started = true;
    app.foreground.addListener(_environmentChanged);
    app.addListener(_inventoryChanged);
    _environmentChanged();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    _timer?.cancel();
    if (_started && app.foreground.value) unawaited(refresh());
  }

  void _inventoryChanged() {
    // Remove credentials' old scope immediately; late responses carry a revision
    // and AppNotifier independently rejects a replaced account or connection.
    final removed = _samples.keys.where((id) {
      final machine = app.stateOf(id);
      return !identical(machine, _samples[id]?.$1) ||
          machine?.connectionStatus != ConnectionStatus.connected;
    }).toList();
    for (final id in removed) {
      _samples.remove(id);
    }
    if (removed.isNotEmpty) {
      _revision++;
      notifyListeners();
    }
  }

  void _environmentChanged() {
    _revision++;
    _timer?.cancel();
    if (app.foreground.value) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _busy || !app.foreground.value) return;
    _timer?.cancel();
    _busy = true;
    final revision = _revision;
    final machines = {for (final row in live) row.machineId: row.machine};
    try {
      final readings = await Future.wait(
        machines.entries.map(
          (entry) async => (
            entry.key,
            entry.value,
            await app.readHarnessResources(entry.key),
          ),
        ),
      );
      if (_disposed || revision != _revision || !app.foreground.value) return;
      _samples.clear();
      for (final (id, machine, result) in readings) {
        if (result != null && identical(machine, app.stateOf(id))) {
          _samples[id] = (machine, result);
        }
      }
      notifyListeners();
    } finally {
      _busy = false;
      if (!_disposed && _started && app.foreground.value) {
        _timer = Timer(Duration(seconds: _expanded ? 3 : 15), refresh);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    if (_started) {
      app.foreground.removeListener(_environmentChanged);
      app.removeListener(_inventoryChanged);
    }
    _samples.clear();
    super.dispose();
  }
}
