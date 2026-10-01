import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_login.dart';
import 'package:harness/auth/sign_in_client.dart';
import 'package:harness/core/config.dart';
import 'package:harness/screens/login_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';

/// The login screen's second way in: a QR a signed-in phone approves, then a yes here to the
/// account that approved it.

/// Shows a QR, then asks the account question, and records the answer — no process started.
class _PhoneLogin extends CliLogin {
  final answers = <bool>[];
  final Completer<void> finished = Completer<void>();

  @override
  Future<void> loginWithPhone({
    required void Function(String link, int expiresIn) onQr,
    required Future<bool> Function(String email) onConfirm,
  }) async {
    onQr('https://harness.autonomous.ai/signin#k=hnq_${'a' * 43}', 120);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    answers.add(await onConfirm('dee@example.com'));
    await finished.future;
    if (!answers.last) throw StateError('Not signed in as dee@example.com.');
  }
}

Widget _host(AppNotifier app) => MaterialApp(
  theme: grid.buildAppTheme(brightness: Brightness.light),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(880, 700)),
    child: grid.BrightnessScope(
      child: ListenableBuilder(listenable: app, builder: (_, _) => LoginScreen(notifier: app)),
    ),
  ),
);

void main() {
  testWidgets('offers "Scan with your phone", shows the QR, then asks whose account', (tester) async {
    grid.AppTheme.brightness.value = Brightness.light;
    final login = _PhoneLogin();
    final app = AppNotifier(config: AppConfig.dev, authSession: AuthSession(), configStore: null, cliLogin: login)
      ..status = AppStatus.unauthenticated;
    addTearDown(app.dispose);
    await tester.pumpWidget(_host(app));
    expect(find.byKey(const Key('login-scan-with-phone')), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-scan-with-phone')));
    await tester.pump();
    expect(find.byKey(const Key('login-phone-qr')), findsOneWidget);
    expect(find.textContaining('Sign in a computer'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Sign in as dee@example.com?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login-phone-refuse')));
    await tester.pump();
    expect(login.answers, [false]);
    login.finished.complete();
    await tester.pump();
    expect(app.signingIn, isFalse);
    expect(find.byKey(const Key('login-scan-with-phone')), findsOneWidget);
  });

  testWidgets('a build that cannot sign in by phone does not offer it', (tester) async {
    grid.AppTheme.brightness.value = Brightness.light;
    final app = AppNotifier(config: AppConfig.dev, authSession: AuthSession(), configStore: null, cliLogin: _SsoOnly())
      ..status = AppStatus.unauthenticated;
    addTearDown(app.dispose);
    await tester.pumpWidget(_host(app));
    expect(find.byKey(const Key('login-scan-with-phone')), findsNothing);
  });
}

class _SsoOnly implements SignInClient {
  @override
  Future<CliAuthStatus> checkStatus() async => const CliAuthStatus(loggedIn: false);
  @override
  Future<void> login({required void Function(String url) onAuthorizeUrl}) async {}
  @override
  void cancel() {}
  @override
  Future<void> logout() async {}
}
