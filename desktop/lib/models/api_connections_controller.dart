import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import '../ws/ws_conn.dart';

/// The UI retains public metadata only. Keys travel once to the selected daemon;
/// replies, preferences, and provider rows never contain them.
class ApiConnection {
  const ApiConnection(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String? ?? '';
  String get provider => data['provider'] as String? ?? 'custom';
  String get name => data['name'] as String? ?? '';
  String get baseUrl => data['baseUrl'] as String? ?? '';
  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;
  String get keyEnv => data['keyEnv'] as String? ?? '';
  String get authHeader => data['authHeader'] as String? ?? 'Authorization';
  String get authPrefix => data['authPrefix'] as String? ?? 'Bearer';
  String? get keyUrl => data['keyUrl'] as String?;
  bool matches(String query) =>
      '$name $baseUrl'.toLowerCase().contains(query.toLowerCase());

  factory ApiConnection.fromJson(Map<String, dynamic> json) => ApiConnection({
    for (final key in [
      'id',
      'provider',
      'name',
      'baseUrl',
      'keyEnv',
      'authHeader',
      'authPrefix',
      'keyUrl',
      'docsUrl',
    ])
      if (json[key] is String) key: json[key],
  });
}

class ApiConnectionsController extends ChangeNotifier {
  ApiConnectionsController(this.app, {String? machineId})
    : _machineId =
          machineId ??
          (app.viewer == null
              ? null
              : app.ownedActionMachine?.machine.machineId) {
    app.addListener(_observe);
    _owner = _target;
    _connected = available;
  }
  final AppNotifier app;
  String? _machineId;
  MachineState? get _target {
    if (_machineId != null) return app.stateOf(_machineId!);
    if (app.viewer == null) return app.localMachineState;
    final machine = app.ownedActionMachine;
    _machineId = machine?.machine.machineId;
    return machine;
  }

  String get hostLabel => app.viewer == null && _machineId == null
      ? 'this computer'
      : _owner?.machine.displayName ?? 'a connected machine';
  String get _connectMessage => 'Connect $hostLabel to manage APIs.';

  /// Called between panels, never while an API editor is open.
  void useMachine(String machineId) {
    if (_disposed || saving || machineId == _machineId) return;
    _machineId = machineId;
    _observe();
  }

  MachineState? _owner;
  bool _disposed = false;
  bool _connected = false;
  int _revision = 0;
  List<ApiConnection> connections = [], presets = [];
  bool loading = false, saving = false, loaded = false;
  String? error;

  bool get available =>
      _owner != null &&
      !_owner!.machine.isShared &&
      !_owner!.needsLink &&
      _owner!.nodeOnline != false &&
      _owner!.connectionStatus == ConnectionStatus.connected;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _observe() {
    if (identical(_owner, _target)) {
      if (_connected != available) {
        _connected = available;
        if (!_connected) error = _connectMessage;
        _changed();
        if (_connected) unawaited(refresh());
      }
      return;
    }
    _owner = _target;
    _connected = available;
    _revision++;
    connections = [];
    presets = [];
    loading = saving = loaded = false;
    error = null;
    unawaited(refresh());
  }

  Future<bool> refresh() => _request({'action': 'list'});
  Future<bool> save(Map<String, dynamic> connection) =>
      _request({'action': 'save', 'connection': connection});
  Future<bool> remove(String id) => _request({'action': 'remove', 'id': id});

  Future<bool> _request(Map<String, dynamic> payload) async {
    if (_disposed || saving) return false;
    final owner = _owner;
    if (owner == null || !available) {
      error = _connectMessage;
      _changed();
      return false;
    }
    final revision = ++_revision;
    final mutation = payload['action'] != 'list';
    loading = true;
    saving = mutation;
    error = null;
    _changed();
    bool current() =>
        !_disposed && revision == _revision && identical(owner, _target);
    try {
      final answer = await app.apiConnections(owner.machine.machineId, payload);
      if (!current()) return false;
      if (answer['error'] != null) {
        error =
            answer['detail'] as String? ?? 'APIs are unavailable. Try again.';
        return false;
      }
      if (answer['connections'] is! List || answer['presets'] is! List) {
        error = 'Update Harness on $hostLabel to connect APIs.';
        return false;
      }
      List<ApiConnection> rows(String key) => (answer[key] as List)
          .whereType<Map<String, dynamic>>()
          .map(ApiConnection.fromJson)
          .toList();
      connections = rows('connections');
      presets = rows('presets');
      loaded = true;
      return true;
    } on WsRequestFailure catch (failure) {
      if (current()) {
        error = failure.detail ?? 'APIs are unavailable. Try again.';
      }
      return false;
    } catch (_) {
      if (current()) {
        error = mutation
            ? 'Could not confirm the change. Go back and refresh.'
            : 'APIs are unavailable. Try again.';
      }
      return false;
    } finally {
      if (current()) {
        loading = saving = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_observe);
    super.dispose();
  }
}
