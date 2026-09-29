import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/api/api_client.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/auth/cli_link.dart';
import 'package:harness_mobile/auth/peer_link_client.dart';
import 'package:harness_mobile/core/config.dart';

import 'package:harness_mobile/e2ee/bytes.dart';
import 'package:harness_mobile/e2ee/keys.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/welcome/connect_code.dart';
import 'package:harness_mobile/phone/welcome/connect_computer.dart';
import 'package:harness_mobile/phone/welcome/scan_to_connect.dart';
import 'package:harness_mobile/phone/welcome/set_up_computer.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/viewer/group_sync.dart';
import 'package:harness_mobile/viewer/viewer_key_store.dart';
import 'package:harness_mobile/viewer/viewer_services.dart';

import 'viewer_app_fixture.dart' show FakeApi;
import 'voice_fakes.dart' show MemoryKeyValueStore;

class _Links implements PeerLinkClient {
  final codes = <(String, String)>[];
  final fingerprints = <String?>[];

  @override
  Future<CliLinkConnectResult> connectWithCode(
    String machineId,
    String code, {
    required String label,
    String? displayName,
    String? expectedFingerprint,
  }) async {
    codes.add((machineId, code));
    fingerprints.add(expectedFingerprint);
    return CliLinkConnectResult(linkedMachineId: machineId);
  }

  @override
  Future<CliLinkConnectResult> connect(
    String machineId,
    String password, {
    void Function(String stage)? onProgress,
    String? displayName,
    String? label,
  }) async => const CliLinkConnectResult(error: 'not used');

  @override
  Future<CliLinkListResult> list() async =>
      const CliLinkListResult(machines: []);

  @override
  Future<String?> unlink(String machineId) async => null;
}

/// A browser's sign-in request, as the backend answers the approving phone.
class _BrowserApi extends FakeApi {
  _BrowserApi(this.pub, this.fp);
  final String pub, fp;
  final approved = <(String, String)>[];
  @override
  Future<MachineSignInRequest> lookupMachineSignIn(String userCode) async =>
      MachineSignInRequest(
        label: 'Chrome on macOS',
        viewer: true,
        fingerprint: fp,
        pub: pub,
      );
  @override
  Future<void> approveBrowserSignIn(
    String userCode, {
    required String sealedRoster,
  }) async => approved.add((userCode, sealedRoster));
}

/// A machine's sign-in request (`harness login`'s QR), as the backend answers the approving phone.
class _MachineApi extends FakeApi {
  _MachineApi(this.pub, this.fp);
  final String pub, fp;
  final approved = <(String, String?)>[];
  @override
  Future<MachineSignInRequest> lookupMachineSignIn(String userCode) async =>
      MachineSignInRequest(label: 'box2', fingerprint: fp, pub: pub);
  @override
  Future<String> approveMachineSignIn(
    String userCode, {
    String? sealedRoster,
  }) async {
    approved.add((userCode, sealedRoster));
    return 'b' * 32;
  }
}

/// Setting up a computer from a signed-in phone is the first screen's download menu, plus what only
/// a signed-in phone can do there: watch for the computer, and pair with it by its code.
void main() {
  late _Links links;
  late AppNotifier app;
  late List<bool> backs;

  setUp(() {
    links = _Links();
    app = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      peerLinks: links,
    );
    // The account's REST API, answered in memory: its machines are asked for again before a
    // scanned computer is looked for, and none is on it unless a test says so.
    app.api = FakeApi();
    backs = [];
  });
  tearDown(() => app.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectComputerPage(
          notifier: app,
          onBack: () => backs.add(true),
          onTrySample: (_) async => null,
          scanCamera: const SizedBox(),
          loadDownloads: () async => const {},
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> scan(WidgetTester tester, String link) async {
    await tester.tap(find.text('Scan to connect ›'));
    await tester.pumpAndSettle();
    tester
        .widget<ScanToConnectPage>(find.byType(ScanToConnectPage))
        .onCode(ConnectCode.parse(link)!);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('the download menu, watching, and the sample to try meanwhile', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(SetUpComputerPage), findsOneWidget);
    expect(find.text('Apple Silicon'), findsOneWidget);
    expect(find.textContaining('Waiting for your computer'), findsOneWidget);
    expect(find.text('Try the sample ›'), findsOneWidget);
    // The old page's second way of saying all this is gone.
    expect(find.text('Email me the setup link'), findsNothing);
    expect(find.textContaining('remote-password'), findsNothing);
    await unmount(tester);
  });

  testWidgets('scanning the new computer\'s code pairs it and goes back', (
    tester,
  ) async {
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio',
    );
    app.machines = [studio];
    app.machineStates['studio'] = MachineState(studio)
      ..nodeOnline = true
      ..needsLink = true;
    await pump(tester);
    await scan(
      tester,
      ConnectCode.link(
        'a@b.co',
        machineId: 'studio',
        pairCode: 'K7QM4XPT',
        fingerprint: '5F8061C46142ADCF',
        hostname: 'studio.local',
      ),
    );
    // Nothing is paired until the person has seen what the code is for.
    expect(links.codes, isEmpty);
    expect(find.text('Add this machine?'), findsOneWidget);
    expect(find.text('5F80·61C4·6142·ADCF'), findsOneWidget);
    expect(find.text('studio.local'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(links.codes, [('studio', 'K7QM4XPT')]);
    // The key the QR named goes with the code, so a different machine answering is not pinned.
    expect(links.fingerprints, ['5F8061C46142ADCF']);
    expect(backs, [true]);
    await unmount(tester);
  });

  testWidgets(
    'a browser\'s sign-in QR: approve signs it in, hands it the group, and takes it in',
    (tester) async {
      final keys = ViewerKeyStore(storage: MemoryKeyValueStore());
      app.dispose();
      app = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
        peerLinks: links,
        viewer: ViewerServices(
          config: AppConfig.dev,
          session: AuthSession(),
          keys: keys,
        ),
      );
      // This phone trusts one machine; the browser has its own key.
      final machinePub = Uint8List.fromList(List.generate(32, (i) => i + 1));
      late E2eeIdentity browser;
      await tester.runAsync(() async {
        await keys.pin('a' * 32, machinePub, label: 'studio');
        browser = await E2eeIdentity.generate();
      });
      final fp = fingerprint(browser.pub).replaceAll('·', '');
      final api = _BrowserApi(b64e(browser.pub), fp);
      app.api = api;
      const studio = Machine(
        machineId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        authMode: MachineAuthMode.remote,
        name: 'studio',
      );
      app.machines = [studio];
      app.machineStates[studio.machineId] = MachineState(studio)
        ..nodeOnline = true;
      await pump(tester);
      await scan(
        tester,
        ConnectCode.signInLink(
          'U' * 26,
          pairCode: 'ABCDEFGHJKMNPQRS',
          fingerprint: fp,
          hostname: 'Chrome on macOS',
          viewer: true,
        ),
      );
      expect(find.text('Sign in this browser?'), findsOneWidget);
      expect(find.text('Chrome on macOS'), findsOneWidget);
      expect(find.textContaining('browser you are using'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      // The confirm page leaves, then the approval runs real crypto: let both finish.
      for (var i = 0; i < 60 && api.approved.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(api.approved, hasLength(1));
      final (userCode, sealed) = api.approved.single;
      expect(userCode, 'U' * 26);
      // Only the QR's code opens it — the backend that carried it cannot.
      expect(
        openHandedRoster(sealed, code: 'WRONGCODEWRONGCD', userCode: userCode),
        isNull,
      );
      final roster = GroupRoster.parse(
        openHandedRoster(sealed, code: 'ABCDEFGHJKMNPQRS', userCode: userCode),
      );
      expect(roster.members.where((m) => m.isMachine).map((m) => m.machineId), [
        'a' * 32,
      ]);
      // The phone itself is in it, so the browser trusts the phone as much as its machines.
      expect(roster.members.where((m) => m.kind == 'viewer'), hasLength(1));
      // And the browser is now in this phone's group, for the next sync to spread.
      late Object? stored;
      await tester.runAsync(() async => stored = await keys.groupRoster());
      expect(
        GroupRoster.parse(stored).members.map((m) => m.pub),
        contains(b64e(browser.pub)),
      );
      // The browser dials nothing through this phone: no pairing code was spent here.
      expect(links.codes, isEmpty);
      expect(backs, [true]);
      await unmount(tester);
    },
  );

  testWidgets(
    'a machine\'s sign-in QR: approve hands it the group and pins it — no dial, no wait',
    (tester) async {
      final keys = ViewerKeyStore(storage: MemoryKeyValueStore());
      app.dispose();
      app = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
        peerLinks: links,
        viewer: ViewerServices(
          config: AppConfig.dev,
          session: AuthSession(),
          keys: keys,
        ),
      );
      final studioPub = Uint8List.fromList(List.generate(32, (i) => i + 1));
      late E2eeIdentity box;
      await tester.runAsync(() async {
        await keys.pin('a' * 32, studioPub, label: 'studio');
        box = await E2eeIdentity.generate();
      });
      final fp = fingerprint(box.pub).replaceAll('·', '');
      final api = _MachineApi(b64e(box.pub), fp);
      app.api = api;
      await pump(tester);
      await scan(
        tester,
        ConnectCode.signInLink(
          'U' * 26,
          pairCode: 'ABCDEFGHJKMNPQRS',
          fingerprint: fp,
          hostname: 'box2',
        ),
      );
      expect(find.text('Sign in & add machine?'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      for (var i = 0; i < 60 && api.approved.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(api.approved, hasLength(1));
      final (userCode, sealed) = api.approved.single;
      final roster = GroupRoster.parse(
        openHandedRoster(sealed!, code: 'ABCDEFGHJKMNPQRS', userCode: userCode),
      );
      expect(roster.members.where((m) => m.isMachine).map((m) => m.machineId), [
        'a' * 32,
      ]);
      // This phone now trusts the machine by the key the QR vouched for, and has it in its group.
      late MachinePeer? pinned;
      late Object? stored;
      await tester.runAsync(() async {
        pinned = await keys.peer('b' * 32);
        stored = await keys.groupRoster();
      });
      expect(pinned?.pub, box.pub);
      expect(
        GroupRoster.parse(stored).members.map((m) => m.machineId),
        contains('b' * 32),
      );
      // Nothing dialled the machine: the keys changed hands in the approval itself.
      expect(links.codes, isEmpty);
      expect(backs, [true]);
      await unmount(tester);
    },
  );

  testWidgets('cancelling "Add this machine?" pairs nothing', (tester) async {
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio',
    );
    app.machines = [studio];
    app.machineStates['studio'] = MachineState(studio)..needsLink = true;
    await pump(tester);
    await scan(
      tester,
      ConnectCode.link('a@b.co', machineId: 'studio', pairCode: 'K7QM4XPT'),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(links.codes, isEmpty);
    expect(backs, isEmpty);
    await unmount(tester);
  });

  testWidgets('a computer on another account is refused, and says so', (
    tester,
  ) async {
    await pump(tester);
    await scan(
      tester,
      ConnectCode.link('a@b.co', machineId: 'elsewhere', pairCode: 'K7QM4XPT'),
    );
    // The page asks for the list again first, and gives that five seconds.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(links.codes, isEmpty);
    expect(backs, isEmpty);
    expect(find.textContaining("isn't on your account"), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an account that cannot be read is said, not left pairing', (
    tester,
  ) async {
    (app.api as FakeApi).onMachines = () async =>
        throw StateError('The network connection was lost.');
    await pump(tester);
    await scan(
      tester,
      ConnectCode.link('a@b.co', machineId: 'studio', pairCode: 'K7QM4XPT'),
    );
    await tester.pump();
    expect(links.codes, isEmpty);
    expect(backs, isEmpty);
    expect(find.text('Pairing…'), findsNothing);
    expect(find.textContaining("Couldn't reach your account"), findsOneWidget);
    await unmount(tester);
  });
}
