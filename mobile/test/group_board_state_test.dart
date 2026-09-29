import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/e2ee/bytes.dart';
import 'package:harness_mobile/e2ee/keys.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/viewer/group_sync.dart';
import 'package:harness_mobile/viewer/viewer_key_store.dart';
import 'package:harness_mobile/viewer/viewer_services.dart';

import 'voice_fakes.dart' show MemoryKeyValueStore;

/// A machine another phone approved reaches this one through the account's board — and its row
/// follows on its own.
void main() {
  final app1 = 'b' * 32;
  late AppNotifier app;
  late ViewerKeyStore keys;
  late E2eeIdentity other, machine;

  setUp(() async {
    keys = ViewerKeyStore(storage: MemoryKeyValueStore());
    app = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      viewer: ViewerServices(
        config: AppConfig.dev,
        session: AuthSession(),
        keys: keys,
      ),
    );
    other = await E2eeIdentity.generate();
    machine = await E2eeIdentity.generate();
    await admitGroupMember(
      keys,
      GroupMember(pub: b64e(other.pub), kind: 'viewer', label: 'web', at: 5),
    );
    app.machineStates[app1] =
        MachineState(
            Machine(
              machineId: app1,
              authMode: MachineAuthMode.remote,
              name: 'app1',
            ),
          )
          ..nodeOnline = true
          ..needsLink = true
          ..agentLoadStatus = AgentLoadStatus.needsLink;
  });
  tearDown(() => app.dispose());

  Future<Map<String, Object>> vouch(E2eeIdentity signer, int at) =>
      signVouch(signer, {
        'pub': b64e(machine.pub),
        'kind': 'machine',
        'machineId': app1,
        'label': 'app1',
        'at': at,
      });

  test('a machine a member vouched for is unlocked, no reload', () async {
    var notified = 0;
    app.addListener(() => notified++);
    await app.adoptGroupBoardForTest([await vouch(other, 10)]);
    expect(app.machineStates[app1]!.needsLink, isFalse);
    expect(app.machineStates[app1]!.agentLoadStatus, AgentLoadStatus.idle);
    expect(notified, greaterThan(0));
  });

  test('a stranger\'s vouch changes nothing', () async {
    await app.adoptGroupBoardForTest([
      await vouch(await E2eeIdentity.generate(), 10),
    ]);
    expect(app.machineStates[app1]!.needsLink, isTrue);
    expect(await keys.peer(app1), isNull);
  });

  test('a machine the group removed is locked again', () async {
    await app.adoptGroupBoardForTest([await vouch(other, 10)]);
    await app.adoptGroupBoardForTest([
      await signVouch(other, {
        'pub': b64e(machine.pub),
        'at': 20,
        'removed': true,
      }),
    ]);
    expect(app.machineStates[app1]!.needsLink, isTrue);
    expect(await keys.peer(app1), isNull);
  });
}
