import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/machine_resources.dart';
import '../core/models.dart';
import 'app_state.dart';

/// Hardware has a machine scope. Session counts and subscription allowances do
/// not. Closed: sample the selected machine. Open: sample the owned inventory.
/// These optional reads never connect a machine or launch a harness.
class MachineResourceMonitor extends ChangeNotifier {
  MachineResourceMonitor(this.app);
  final AppNotifier app;
  final _samples = <String, (MachineState, MachineResources, DateTime)>{};
  Timer? _timer;
  String? _pinnedMachineId, _lastScope;
  bool _started = false, _disposed = false, _busy = false, _again = false;
  bool _expanded = false;
  int _revision = 0;

  bool get followsFocus => _pinnedMachineId == null;
  List<MachineState> get machines =>
      app.machineStates.values
          .where((state) => !state.machine.isShared)
          .toList()
        ..sort(
          (a, b) => a.machine.displayName.toLowerCase().compareTo(
            b.machine.displayName.toLowerCase(),
          ),
        );

  MachineState? get selected {
    final id =
        _pinnedMachineId ?? app.focusedPane?.machineId ?? app.selectedMachineId;
    if (id != null) {
      final state = app.stateOf(id);
      if (state != null) return state.machine.isShared ? null : state;
    }
    return machines.where((m) => m.isLocalMachine).firstOrNull ??
        machines.where(available).firstOrNull ??
        machines.firstOrNull;
  }

  bool available(MachineState state) =>
      !state.machine.isShared &&
      !state.needsLink &&
      state.nodeOnline != false &&
      state.connectionStatus == ConnectionStatus.connected;

  MachineResources? reading(MachineState? state) {
    if (state == null || !available(state)) return null;
    final sample = _samples[state.machine.machineId];
    return identical(sample?.$1, state) &&
            DateTime.now().difference(sample!.$3) <= const Duration(seconds: 45)
        ? sample.$2
        : null;
  }

  String get scopeName => selected?.machine.displayName ?? 'Resources';
  String metricsLabel({bool gpu = true}) {
    final value = reading(selected);
    return '    CPU ${resourcePercent(value?.cpuPercent, padded: true)}'
        '    RAM ${resourcePercent(value?.memoryPercent, padded: true)}'
        '${gpu ? '    GPU ${resourcePercent(value?.busiestGpu?.utilizationPercent, padded: true)}' : ''}';
  }

  String get label {
    return '$scopeName${metricsLabel()}';
  }

  String get detail {
    final state = selected, value = reading(state);
    return '$label\n'
        '${followsFocus ? 'Follows the focused pane.' : 'Pinned to $scopeName.'} '
        'CPU and RAM show this machine’s usage, including other apps.\n'
        '${value?.busiestGpu == null ? 'GPU reading unavailable.' : 'GPU shows the busiest device: ${value!.busiestGpu!.name}.'}\n'
        '${state != null && !available(state) ? 'Machine disconnected. ' : ''}'
        'Click to compare machines. Unavailable readings show --.';
  }

  void selectMachine(String? id) {
    if (id != null && !machines.any((m) => m.machine.machineId == id)) return;
    if (_pinnedMachineId == id) return;
    _pinnedMachineId = id;
    _revision++;
    _lastScope = null;
    _inventoryChanged();
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    app.addListener(_inventoryChanged);
    app.foreground.addListener(_environmentChanged);
    _environmentChanged();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    _revision++;
    _timer?.cancel();
    if (_started) unawaited(refresh());
  }

  void _inventoryChanged() {
    if (_pinnedMachineId != null && app.stateOf(_pinnedMachineId!) == null) {
      _pinnedMachineId = null;
    }
    final removed = _samples.keys.where((id) {
      final state = app.stateOf(id);
      return state == null ||
          !identical(state, _samples[id]!.$1) ||
          !available(state);
    }).toList();
    for (final id in removed) {
      _samples.remove(id);
    }
    if (removed.isNotEmpty) _revision++;
    final state = selected;
    final scope =
        '${state?.machine.machineId}/${state == null ? false : available(state)}';
    final changed = scope != _lastScope;
    _lastScope = scope;
    notifyListeners();
    if (_started && (changed || removed.isNotEmpty)) unawaited(refresh());
  }

  void _environmentChanged() {
    _revision++;
    _timer?.cancel();
    _samples.clear();
    notifyListeners();
    if (app.foreground.value) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || !app.foreground.value) return;
    if (_busy) {
      _again = true;
      return;
    }
    _timer?.cancel();
    _busy = true;
    final revision = _revision;
    final scope = selected;
    final targets = (_expanded ? machines : [?scope]).where(available).toList();
    try {
      await Future.wait(
        targets.map((state) async {
          final id = state.machine.machineId;
          final value = await app.readMachineResources(id);
          if (_disposed ||
              revision != _revision ||
              !identical(app.stateOf(id), state) ||
              !available(state)) {
            return;
          }
          if (value == null) {
            _samples.remove(id);
          } else {
            _samples[id] = (state, value, DateTime.now());
          }
          notifyListeners();
        }),
      );
    } finally {
      _busy = false;
      if (!_disposed && _started && app.foreground.value) {
        if (_again) {
          _again = false;
          unawaited(refresh());
        } else {
          _timer = Timer(Duration(seconds: _expanded ? 3 : 15), refresh);
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    if (_started) {
      app.removeListener(_inventoryChanged);
      app.foreground.removeListener(_environmentChanged);
    }
    _samples.clear();
    super.dispose();
  }
}
