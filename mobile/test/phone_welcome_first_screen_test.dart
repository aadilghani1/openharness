import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/phone/welcome/connect_code.dart';
import 'package:harness_mobile/phone/welcome/phone_welcome.dart';
import 'package:harness_mobile/phone/welcome/scan_to_connect.dart';
import 'package:harness_mobile/phone/welcome/set_up_computer.dart';
import 'package:harness_mobile/state/app_state.dart';

/// The first screen: what Harness is, one question, and its two answers — scan the code the
/// desktop app shows, or get Harness onto the computer.
void main() {
  group('ConnectCode', () {
    test('reads the desktop app\'s link, all of it in the fragment', () {
      final code = ConnectCode.parse(
        ConnectCode.link('ada@example.com', machineId: 'm1', pairCode: 'K7QM'),
      )!;
      expect(code.email, 'ada@example.com');
      expect(code.machineId, 'm1');
      expect(code.pairCode, 'K7QM');
      // Nothing secret where a browser would send it.
      expect(
        Uri.parse(ConnectCode.link('a@b.co', pairCode: 'K7QM')).query,
        isEmpty,
      );
    });

    test('ignores codes that are not ours', () {
      expect(ConnectCode.parse('https://example.com/pair#e=a@b.co'), isNull);
      expect(
        ConnectCode.parse('http://harness.autonomous.ai/pair#e=a@b.co'),
        isNull,
      );
      expect(
        ConnectCode.parse('https://harness.autonomous.ai/pair#m=m1'),
        isNull,
      );
      expect(ConnectCode.parse('not a link'), isNull);
    });
  });

  late AppNotifier notifier;
  late List<String> sent;

  setUp(() {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    sent = [];
  });
  tearDown(() => notifier.dispose());

  Future<void> pump(WidgetTester tester, {Widget? camera}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneWelcome(
          notifier: notifier,
          sendCode: (email) async => sent.add(email),
          signIn: (_, _) async {},
          scanCamera: camera ?? const SizedBox(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('one question, two answers, and nothing else', (tester) async {
    await pump(tester);
    expect(find.text('Is Harness on your computer?'), findsOneWidget);
    expect(find.text('Yes — scan to connect'), findsOneWidget);
    expect(find.text('Not yet — set it up'), findsOneWidget);
    expect(find.text('Continue with email'), findsNothing);
    expect(find.text('Try it first'), findsNothing);
  });

  testWidgets(
    'not yet: the app\'s link to send to the Mac, and the terminal last',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Not yet — set it up'));
      await tester.pump();
      expect(find.byType(SetUpComputerPage), findsOneWidget);
      expect(find.text('Send link to my Mac'), findsOneWidget);
      expect(find.text('harness.autonomous.ai/download'), findsOneWidget);
      expect(
        find.textContaining('https://harness.autonomous.ai/install.sh'),
        findsOneWidget,
      );
      // Back is the first screen.
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump();
      expect(find.text('Is Harness on your computer?'), findsOneWidget);
    },
  );

  testWidgets('a scanned code fills in the account and sends its code', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Yes — scan to connect'));
    await tester.pump();
    final page = tester.widget<ScanToConnectPage>(
      find.byType(ScanToConnectPage),
    );
    page.onCode(ConnectCode.parse(ConnectCode.link('ada@example.com'))!);
    await tester.pump();
    await tester.pump();
    expect(sent, ['ada@example.com']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('ada@example.com'), findsOneWidget);
  });

  testWidgets('no code at hand: email instead', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Yes — scan to connect'));
    await tester.pump();
    await tester.tap(find.text('Use email instead'));
    await tester.pump();
    expect(find.text('Your email'), findsOneWidget);
  });
}
