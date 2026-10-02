import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/harness_resources.dart';
import '../core/models.dart';
import '../shared/theme/workspace_bar_style.dart'
    show workspaceBarGroupSeparator;
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
  final _receivedAt = <String, DateTime>{};
  int _revision = 0;

  List<HarnessSession> get sessions => harnessSessions(app, includeLive: true);
  List<HarnessSession> get live => sessions
      .where((row) => row.live && !row.machine.machine.isShared)
      .toList();

  HarnessResources? reading(HarnessSession row) {
    final snapshot = _samples[row.machineId];
    return row.running &&
            identical(snapshot?.$1, row.machine) &&
            _fresh(row.machineId)
        ? snapshot?.$2.agents[row.agent.id]
        : null;
  }

  bool _fresh(String id) =>
      _receivedAt[id] != null &&
      DateTime.now().difference(_receivedAt[id]!) <=
          const Duration(seconds: 45);

  /// Shared-server RSS belongs to the server, not to each conversation.
  /// Count it once per machine/profile and label it separately in the panel.
  List<HarnessResources> get sharedReadings {
    final rows = live;
    return [
      for (final entry in _samples.entries)
        if (identical(app.stateOf(entry.key), entry.value.$1) &&
            _fresh(entry.key))
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

  String get label => 'Harnesses ${live.length}';

  /// CPU percentages share a denominator (one core), not host capacities.
  /// Totals include available readings; the tooltip explains partial coverage.
  String metricsLabel({bool ram = true, bool gpu = true, bool storage = true}) {
    final readings = [...live.map(reading), ...sharedReadings];
    String total(
      double? Function(HarnessResources) value,
      String Function(double) format,
    ) {
      final known = readings
          .map((r) => r == null ? null : value(r))
          .whereType<double>()
          .toList();
      if (readings.isEmpty) return format(0);
      if (known.isEmpty) return '—';
      return format(known.fold(0, (a, b) => a + b));
    }

    final cpu = total((r) => r.cpuPercent, (v) => '${v.round()}%');
    final memory = total((r) => r.memoryBytes, _wholeBytes);
    final graphics = total((r) => r.gpuPercent, (v) => '${v.round()}%');
    return 'CPU $cpu'
        '${ram ? '${workspaceBarGroupSeparator}RAM $memory' : ''}'
        '${gpu ? '${workspaceBarGroupSeparator}GPU $graphics' : ''}'
        '${storage ? '${workspaceBarGroupSeparator}SSD ${_storageLabel()}' : ''}';
  }

  static String _wholeBytes(double bytes) => bytes >= 1e9
      ? '${(bytes / 1e9).round()} GB'
      : '${(bytes / 1e6).round()} MB';

  String _storageLabel() {
    final folders = <String, Map<String, double?>>{};
    for (final row in live) {
      final resource = reading(row), path = resource?.workspacePath;
      if (path == null || resource?.workspaceBytes == null) {
        continue;
      }
      (folders[row.machineId] ??= {})[path] = resource!.workspaceBytes;
    }
    var bytes = 0.0, count = 0;
    for (final machine in folders.values) {
      final included = <String>[];
      for (final path
          in machine.keys.toList()
            ..sort((a, b) => a.length.compareTo(b.length))) {
        if (included.any(
          (parent) => path == parent || path.startsWith('$parent/'),
        )) {
          continue;
        }
        included.add(path);
        count++;
        bytes += machine[path]!;
      }
    }
    if (live.isNotEmpty && count == 0) return '—';
    return _wholeBytes(bytes);
  }

  String get resourceDetail =>
      '${live.length} open harnesses across connected machines. Totals cover these harnesses only.\n'
      '${metricsLabel()}\n'
      'CPU: 100% is one core. RAM includes child processes and shared servers counted once; shared memory pages can overlap.\n'
      'GPU: harness process GPU use on supported macOS and Linux NVIDIA drivers. First samples and unavailable counters show —. Cloud model GPU usage is not reported.\n'
      'SSD: workspace disk space, shared and nested folders counted once per machine. Files remain after stopping.\n'
      'Totals include available readings and may be partial. — means unavailable. Click to open Harness Monitor.';

  String get detail =>
      '${live.length} open across connected machines, including idle and starting harnesses. Click to open Harness Monitor.\n'
      '${HarnessResources.explanation}${sharedLabel == null ? '' : '\n$sharedLabel, included once in the session monitor.'}';

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
      _receivedAt.remove(id);
    }
    if (removed.isNotEmpty) _revision++;
    notifyListeners();
  }

  void _environmentChanged() {
    _revision++;
    _timer?.cancel();
    _samples.clear();
    _receivedAt.clear();
    notifyListeners();
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
          _receivedAt[id] = DateTime.now();
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
