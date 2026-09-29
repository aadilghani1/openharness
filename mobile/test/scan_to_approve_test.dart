import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/welcome/connect_code.dart';
import 'package:harness_mobile/phone/welcome/scan_to_connect.dart';

/// "Scan a QR code" on a signed-in phone: the camera, or — this app opens no links — the
/// `…/pair#…` link a computer prints beside its QR, pasted.
void main() {
  Future<List<ConnectCode>> pump(
    WidgetTester tester, {
    required String? clipboard,
    bool allowPaste = true,
  }) async {
    final codes = <ConnectCode>[];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanToConnectPage(
            camera: const SizedBox(),
            fallbackLabel: 'Not now',
            title: 'Scan the QR on the computer or browser signing in',
            hint: '`harness login`, the desktop app, or Harness on the web',
            allowPaste: allowPaste,
            readClipboard: () async => clipboard,
            onCode: codes.add,
            onUseEmail: () {},
            onBack: () {},
          ),
        ),
      ),
    );
    return codes;
  }

  testWidgets('a pasted browser sign-in link is read as one', (tester) async {
    final link = ConnectCode.signInLink(
      'U' * 26,
      pairCode: 'ABCDEFGHJKMNPQRS',
      fingerprint: 'AB12CD34EF567890',
      hostname: 'Chrome on macOS',
      viewer: true,
      base: Uri.parse('http://127.0.0.1:8080'),
    );
    final codes = await pump(tester, clipboard: link);
    expect(
      find.text('Scan the QR on the computer or browser signing in'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('scan-paste-link')));
    await tester.pump();
    expect(codes.single.isViewerSignIn, isTrue);
    expect(codes.single.pairCode, 'ABCDEFGHJKMNPQRS');
  });

  testWidgets('a pasted machine sign-in link is read as one', (tester) async {
    final codes = await pump(
      tester,
      clipboard: ConnectCode.signInLink(
        'V' * 26,
        pairCode: 'ABCDEFGHJKMNPQRS',
        fingerprint: '5F8061C46142ADCF',
        hostname: 'machine-remote-2',
      ),
    );
    await tester.tap(find.byKey(const Key('scan-paste-link')));
    await tester.pump();
    expect(codes.single.isSignIn, isTrue);
    expect(codes.single.isViewerSignIn, isFalse);
  });

  testWidgets('anything else on the clipboard says so, and reads nothing', (
    tester,
  ) async {
    final codes = await pump(tester, clipboard: 'hello world');
    await tester.tap(find.byKey(const Key('scan-paste-link')));
    await tester.pump();
    expect(codes, isEmpty);
    expect(find.byKey(const Key('scan-paste-error')), findsOneWidget);
  });

  testWidgets('the sign-in-by-scan pages keep no paste of their own', (
    tester,
  ) async {
    await pump(tester, clipboard: null, allowPaste: false);
    expect(find.byKey(const Key('scan-paste-link')), findsNothing);
  });
}
