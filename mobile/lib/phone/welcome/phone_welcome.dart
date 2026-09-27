import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';

import '../find_row.dart';
import '../tty.dart';
import '../tty_controls.dart';

/// The phone's first screen, signed out: what Harness is in one breath, a glimpse of it working,
/// and the two ways in — sign in, or try a sample first.
///
/// ```
/// harness▌
///
/// Your coding agents,
/// in your pocket.
///
///   fix-login                     working
///   ⏺ 42 tests passed
///   api-tests                      asking
///   "Push the branch to origin?"
///
/// Claude Code and Codex keep working on your
/// computer. Watch them, answer them and start
/// new ones — from here.
///
/// [            Sign in            ]
///        Try a sample first
/// ```
///
/// Signing in is two short steps on this same screen: the email, then the four-digit code — the
/// phone never goes to a browser (see `viewer/email_code_api.dart`).
class PhoneWelcome extends StatefulWidget {
  const PhoneWelcome({
    super.key,
    required this.notifier,
    this.onTrySample,
    this.sendCode,
    this.signIn,
  });

  final AppNotifier notifier;

  /// Stand-ins for the account service, for tests and renders. Null uses [notifier]'s.
  final Future<void> Function(String email)? sendCode;
  final Future<void> Function(String email, String code)? signIn;

  /// Opens the offline sample; completes when it is left, with `'set-up'` when it was left to set
  /// up a real computer. Null leaves the way out.
  final Future<Object?> Function(BuildContext context)? onTrySample;

  @override
  State<PhoneWelcome> createState() => _PhoneWelcomeState();
}

enum _Step { hello, email, code }

class _PhoneWelcomeState extends State<PhoneWelcome> {
  _Step _step = _Step.hello;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  String? _sentTo;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  static const _codeLength = 4;
  static const _resendAfter = 30;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// The sample, and — when it was left from its end card to set up a computer — the set-up page.
  Future<void> _trySample() async {
    final result = await widget.onTrySample!(context);
    if (!mounted || result != 'set-up') return;
    _openSetUp();
  }

  /// Setting up a computer starts with signing in here: the computer signs in with the same
  /// email, and only a signed-in phone can watch for it to appear and address the steps to you.
  /// Signed in, home IS the set-up page — see `ConnectComputerPage`.
  void _openSetUp() {
    setState(() => _forSetUp = true);
    _go(_Step.email);
  }

  /// Signing in on the way to setting up a computer — the email step says why it comes first.
  bool _forSetUp = false;

  void _go(_Step step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (step == _Step.email) _emailFocus.requestFocus();
    if (step == _Step.code) _codeFocus.requestFocus();
    if (step == _Step.hello) {
      FocusManager.instance.primaryFocus?.unfocus();
      _forSetUp = false;
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'That doesn’t look like an email address.');
      return;
    }
    final ok = await _run(
      () => (widget.sendCode ?? widget.notifier.sendLoginCode)(email),
    );
    if (!ok || !mounted) return;
    _sentTo = email;
    _code.clear();
    _startResend();
    _go(_Step.code);
  }

  Future<void> _signIn() async {
    final email = _sentTo, code = _code.text.trim();
    if (email == null) return;
    if (code.length < _codeLength) {
      setState(() => _error = 'Enter the $_codeLength digits from the email.');
      return;
    }
    await _run(
      () => widget.signIn != null
          ? widget.signIn!(email, code)
          : widget.notifier.signInWithCode(email: email, code: code),
    );
  }

  Future<bool> _run(Future<void> Function() request) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await request();
    } catch (e) {
      error = _plain(e.toString());
    }
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _error = error;
    });
    return error == null;
  }

  /// A service's reason, without the exception's type in front of it.
  static String _plain(String raw) =>
      raw.replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '');

  void _startResend() {
    _resendTimer?.cancel();
    _resendIn = _resendAfter;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final tty = Tty.of(context);
    final signingIn = widget.notifier.signingIn;
    return PopScope(
      canPop: _step == _Step.hello,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _go(_step == _Step.code ? _Step.email : _Step.hello);
      },
      child: Scaffold(
        backgroundColor: tty.ground,
        body: SafeArea(
          child: switch (_step) {
            _Step.hello => _Hello(
              onSignIn: () => _go(_Step.email),
              onNewHere: _openSetUp,
              onTrySample: widget.onTrySample == null
                  ? null
                  : () => unawaited(_trySample()),
            ),
            _Step.email => _Form(
              onBack: () => _go(_Step.hello),
              title: _forSetUp ? 'First, your email' : 'Your email',
              lines: [
                _forSetUp
                    ? 'Your computer signs in to Harness with the same email, so it comes first. We’ll send you a 4-digit code.'
                    : 'We’ll send you a 4-digit code. You’ll sign in with this email on your computer too.',
              ],
              field: TtyField(
                key: const Key('welcome-email'),
                controller: _email,
                focus: _emailFocus,
                hint: 'you@example.com',
                action: TextInputAction.go,
                onSubmitted: _sendCode,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              error: _error,
              button: TtyPrimaryButton(
                label: 'Send code',
                busy: _busy,
                busyLabel: 'Sending…',
                onPressed: _sendCode,
              ),
            ),
            _Step.code => _Form(
              onBack: () => _go(_Step.email),
              title: 'Check your email',
              lines: [
                'We sent a $_codeLength-digit code to ${_sentTo ?? 'your email'}.',
              ],
              field: _CodeField(
                controller: _code,
                focus: _codeFocus,
                length: _codeLength,
                onFilled: _signIn,
              ),
              error: _error,
              button: TtyPrimaryButton(
                label: 'Sign in',
                busy: _busy || signingIn,
                busyLabel: 'Signing in…',
                onPressed: _signIn,
              ),
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TtyTextButton(
                      label: _resendIn > 0
                          ? 'Resend in ${_resendIn}s'
                          : 'Resend code',
                      onPressed: _resendIn > 0 || _busy ? null : _sendCode,
                    ),
                  ),
                  Flexible(
                    child: TtyTextButton(
                      label: 'Change email',
                      onPressed: _busy ? null : () => _go(_Step.email),
                    ),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// The first thing anyone sees.
class _Hello extends StatelessWidget {
  const _Hello({
    required this.onSignIn,
    required this.onNewHere,
    this.onTrySample,
  });

  final VoidCallback onSignIn;
  final VoidCallback onNewHere;
  final VoidCallback? onTrySample;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final hero = tty
        .style(size: 26, weight: FontWeight.w700)
        .copyWith(height: 1.2, letterSpacing: -0.5);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      TtyText(
                        'harness',
                        size: TtySize.title,
                        weight: FontWeight.w700,
                      ),
                      Container(
                        width: 9,
                        height: 18,
                        margin: const EdgeInsets.only(left: 2),
                        color: tty.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text('Your coding agents,\nin your pocket.', style: hero),
                  const SizedBox(height: 28),
                  const _Glimpse(),
                  const SizedBox(height: 28),
                  Text(
                    'Claude Code and Codex keep working on your computer. '
                    'Watch them, answer them and start new ones — by voice, '
                    'from anywhere.',
                    style: tty.style(size: TtySize.row, color: tty.faint),
                  ),
                  const Spacer(),
                  const SizedBox(height: 24),
                  TtyPrimaryButton(
                    label: 'Continue with email',
                    onPressed: onSignIn,
                  ),
                  const SizedBox(height: 4),
                  if (onTrySample != null)
                    Center(
                      child: TtyTextButton(
                        label: 'Try it — no computer needed',
                        onPressed: onTrySample,
                      ),
                    ),
                  // No 'Set up my computer' here: it began with the same email as Continue.
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          LucideIcons.lock300,
                          size: 13,
                          color: tty.faint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'End-to-end encrypted. Your code stays on your computer.',
                          style: tty.style(
                            size: TtySize.meta,
                            color: tty.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glimpse of Harness at work — three harnesses as Find lists them, one working, one asking,
/// one done. Not live; a picture of what is on the other side of Sign in.
class _Glimpse extends StatelessWidget {
  const _Glimpse();

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ttyRaised(tty),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              FindRow(
                title: 'fix-login',
                detail: '✓ 42 tests passed · 1 fixed',
                state: 'working',
                stateColor: tty.green,
              ),
              FindRow(
                title: 'api-tests',
                detail: '"Push the branch to origin?"',
                detailColor: tty.text,
                state: 'asking',
                stateColor: tty.yellow,
              ),
              FindRow(
                title: 'docs-site',
                detail: 'laptop:site · main · 3m',
                state: 'done',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One step of signing in: back, a title, a line or two, a field, the button.
class _Form extends StatelessWidget {
  const _Form({
    required this.onBack,
    required this.title,
    required this.lines,
    required this.field,
    required this.button,
    this.error,
    this.footer,
  });

  final VoidCallback onBack;
  final String title;
  final List<String> lines;
  final Widget field;
  final Widget button;
  final String? error;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TtyTextButton(label: '‹ Back', onPressed: onBack),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            children: [
              TtyText(title, size: 24, weight: FontWeight.w700),
              const SizedBox(height: 12),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    line,
                    style: tty.style(size: TtySize.row, color: tty.faint),
                  ),
                ),
              const SizedBox(height: 18),
              AutofillGroup(child: field),
              if (error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '✗ $error',
                    style: tty.style(size: TtySize.meta, color: tty.red),
                  ),
                ),
              const SizedBox(height: 16),
              button,
              ?footer,
            ],
          ),
        ),
      ],
    );
  }
}

/// The code, typed into one wide field in big mono digits — it submits itself on the last one.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.focus,
    required this.length,
    required this.onFilled,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int length;
  final VoidCallback onFilled;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: ttyRaised(tty),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: TextField(
        key: const Key('welcome-code'),
        controller: controller,
        focusNode: focus,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        maxLength: length,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        cursorColor: tty.green,
        style: tty
            .style(size: 30, weight: FontWeight.w700)
            .copyWith(letterSpacing: 18),
        onChanged: (value) {
          if (value.length == length) onFilled();
        },
        decoration: InputDecoration(
          isCollapsed: true,
          counterText: '',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: '•' * length,
          hintStyle: tty
              .style(size: 30, color: tty.dim)
              .copyWith(letterSpacing: 18),
        ),
      ),
    );
  }
}
