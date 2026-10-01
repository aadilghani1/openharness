import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/state/harness_monitor_controller.dart';

import 'model_manager.dart';

class MonitorConnection extends ModelManagerConnection {
  List<Map<String, dynamic>>? inventory;
  int inventoryReads = 0;
  @override
  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 10),
  }) async {}

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (type == 'agents_list' && inventory != null) {
      inventoryReads++;
      return {'agents': inventory};
    }
    final result = await super.request(
      type,
      payload: payload,
      timeout: timeout,
    );
    if (result['agent'] case final Map<String, dynamic> agent
        when agent['dsh'] == harnessMonitorId) {
      return {
        ...result,
        'agent': {
          ...agent,
          'engine': 'opencode',
          'viewerUrl': 'http://127.0.0.1:4179/',
          'viewerName': harnessMonitorName,
        },
      };
    }
    return result;
  }
}

class MonitorTestApp extends ModelManagerTestApp {
  MonitorTestApp(MonitorConnection super.connection);

  @override
  Future<void> probeDsh(String machineId, {bool force = false}) async {
    await probeReply?.future;
    if (probeError != null) throw StateError(probeError!);
    stateOf(machineId)!.dsh.replace([
      DshEntry(
        id: harnessMonitorId,
        name: harnessMonitorName,
        engine: 'opencode',
        description: '',
        installed: installed,
      ),
    ]);
  }
}
