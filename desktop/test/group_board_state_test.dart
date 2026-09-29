import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/keys.dart' show E2eeIdentity;
import 'package:harness/state/app_state.dart';
import 'package:harness/viewer/group_sync.dart';
import 'package:harness/viewer/viewer_key_store.dart';
import 'package:harness/viewer/viewer_services.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_state_test.dart' show MemoryStore;

class _Connection extends WsConn {
  _Connection(String id)
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: id,
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );
}

/// web1 was approved by a phone that had no machine; the phone then approved app1. web1 hears of app1
/// only through the account's board — and its row must follow on its own.
void main() {
  final app1 = 'b' * 32;
  late AppNotifier app;
  late ViewerKeyStore keys;
  late E2eeIdentity phone, machine;

  setUp(() async {
    final session = AuthSession(storage: MemoryStore());
    keys = ViewerKeyStore(storage: MemoryStore());
    app = AppNotifier(
      config: AppConfig.dev,
      authSession: session,
      configStore: null,
      viewer: ViewerServices(
        config: AppConfig.dev,
        session: session,
        keys: keys,
      ),
      connectionForTest: _Connection.new,
    );
    phone = await E2eeIdentity.generate();
    machine = await E2eeIdentity.generate();
    await admitGroupMember(
      keys,
      GroupMember(pub: b64e(phone.pub), kind: 'viewer', label: 'phone', at: 5),
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

  test('a machine the phone vouched for connects, no reload', () async {
    var notified = 0;
    app.addListener(() => notified++);
    await app.adoptGroupBoardForTest([
      await signVouch(phone, {
        'pub': b64e(machine.pub),
        'kind': 'machine',
        'machineId': app1,
        'label': 'app1',
        'at': 10,
      }),
    ]);
    expect(app.machineStates[app1]!.needsLink, isFalse);
    expect(app.machineStates[app1]!.agentLoadStatus, AgentLoadStatus.idle);
    expect((await keys.peer(app1))!.pub, machine.pub);
    expect(notified, greaterThan(0));
  });

  test('a stranger\'s vouch changes nothing', () async {
    final stranger = await E2eeIdentity.generate();
    await app.adoptGroupBoardForTest([
      await signVouch(stranger, {
        'pub': b64e(machine.pub),
        'kind': 'machine',
        'machineId': app1,
        'label': 'app1',
        'at': 10,
      }),
    ]);
    expect(app.machineStates[app1]!.needsLink, isTrue);
    expect(await keys.peer(app1), isNull);
  });

  test('a machine the group removed goes back to "Link required"', () async {
    await app.adoptGroupBoardForTest([
      await signVouch(phone, {
        'pub': b64e(machine.pub),
        'kind': 'machine',
        'machineId': app1,
        'label': 'app1',
        'at': 10,
      }),
    ]);
    expect(app.machineStates[app1]!.needsLink, isFalse);
    await app.adoptGroupBoardForTest([
      await signVouch(phone, {
        'pub': b64e(machine.pub),
        'at': 20,
        'removed': true,
      }),
    ]);
    expect(app.machineStates[app1]!.needsLink, isTrue);
    expect(await keys.peer(app1), isNull);
  });
}
