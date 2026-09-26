import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';

import '../tty.dart';
import '../tty_controls.dart';

/// The commands that put Harness on a computer, in order — the README's "Get started".
const kSetUpCommands = [
  'curl -fsSL https://harness.autonomous.ai/cli/install.sh | bash',
  'harness login',
  'harness remote-password set',
  'harness start',
];

/// Where the desktop app is downloaded.
const kDesktopAppUrl = 'https://harness.autonomous.ai/desktop';

/// How to put Harness on a computer, for someone who has not — the one idea a phone app for agents
/// has to get across first: **the agents run on your computer, and the phone connects to it.**
///
/// Two ways, the app or a terminal, each with its steps to copy. Signed in, the page also watches
/// for the computer to appear (every few seconds, since nothing tells the phone), and the app moves
/// on by itself the moment it does. Signed out, it is the "New here?" page behind the welcome.
class ConnectComputerPage extends StatefulWidget {
  const ConnectComputerPage({
    super.key,
    required this.notifier,
    this.signedIn = true,
    this.onBack,
    this.onTrySample,
  });

  final AppNotifier notifier;

  /// Watch for the computer and say whose account it must be signed in to.
  final bool signedIn;

  /// Shown as `‹ Back` when set.
  final VoidCallback? onBack;

  final void Function(BuildContext context)? onTrySample;

  @override
  State<ConnectComputerPage> createState() => _ConnectComputerPageState();
}

class _ConnectComputerPageState extends State<ConnectComputerPage> {
  Timer? _watch;
  String? _copied;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    if (widget.signedIn) {
      // Nothing pushes a new machine to the phone: ask again every few seconds while this is up.
      _watch = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) unawaited(widget.notifier.refreshMachines());
      });
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _copy(String what, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    HapticFeedback.lightImpact();
    _copiedTimer?.cancel();
    setState(() => _copied = what);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final tty = Tty.of(context);
    final email = widget.notifier.currentUser?.email;
    final account = email == null ? 'the same account' : email;
    return Scaffold(
      backgroundColor: tty.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TtyTextButton(label: '‹ Back', onPressed: widget.onBack),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  TtyText(
                    'Set up your computer',
                    size: 24,
                    weight: FontWeight.w700,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Harness runs Claude Code and Codex on your own computer. '
                    'This phone connects to it — so it starts there.',
                    style: tty.style(size: TtySize.row, color: tty.faint),
                  ),
                  const SizedBox(height: 28),
                  _Step(
                    number: '1',
                    title: 'On a Mac, get the Harness app',
                    children: [
                      _CopyLine(
                        text: 'harness.autonomous.ai/desktop',
                        copied: _copied == 'link',
                        onCopy: () => _copy('link', kDesktopAppUrl),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in with $account, then open Machines → '
                        'this computer → Set password.',
                        style: tty.style(size: TtySize.meta, color: tty.faint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Step(
                    number: '2',
                    title: 'Or, in any terminal',
                    children: [
                      _CommandBlock(
                        lines: kSetUpCommands,
                        copied: _copied == 'commands',
                        onCopy: () =>
                            _copy('commands', kSetUpCommands.join('\n')),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          style: tty.style(
                            size: TtySize.meta,
                            color: tty.faint,
                          ),
                          children: [
                            TextSpan(
                              text: 'harness login',
                              style: tty.style(
                                size: TtySize.meta,
                                color: tty.green,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' signs the computer in to $account. The '
                                  'password you set is what this phone unlocks '
                                  'it with — it never leaves your devices.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (widget.signedIn) const _Watching(),
                  if (widget.onTrySample != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TtyTextButton(
                        label: widget.signedIn
                            ? 'Try a sample while you wait'
                            : 'Try a sample first',
                        onPressed: () => widget.onTrySample!(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered step: `1  Title`, and what to do under it.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.children,
  });

  final String number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: TtyText(
            number,
            color: tty.green,
            size: TtySize.row,
            weight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: tty.style(size: TtySize.row, weight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

/// One line to copy — a link — with `Copy` at its end.
class _CopyLine extends StatelessWidget {
  const _CopyLine({
    required this.text,
    required this.copied,
    required this.onCopy,
  });

  final String text;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ttyRaised(tty),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Expanded(
            child: TtyText(text, size: TtySize.meta, color: tty.text),
          ),
          TtyTextButton(
            label: copied ? 'Copied' : 'Copy',
            color: copied ? tty.green : null,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

/// Commands as a terminal would show them, `$ ` in front of each, and `Copy all` under them.
class _CommandBlock extends StatelessWidget {
  const _CommandBlock({
    required this.lines,
    required this.copied,
    required this.onCopy,
  });

  final List<String> lines;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ttyRaised(tty),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: r'$ ',
                      style: tty.style(color: tty.green, size: TtySize.meta),
                    ),
                    TextSpan(
                      text: line,
                      style: tty.style(size: TtySize.meta),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TtyTextButton(
              label: copied ? 'Copied' : 'Copy all',
              color: copied ? tty.green : null,
              onPressed: onCopy,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Looking for your computer…` with a terminal spinner — the page is watching.
class _Watching extends StatefulWidget {
  const _Watching();

  @override
  State<_Watching> createState() => _WatchingState();
}

class _WatchingState extends State<_Watching> {
  // The terminal's oldest spinner — every monospace face has these four.
  static const _frames = ['|', '/', '-', r'\'];
  int _frame = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TtyText(_frames[_frame], color: tty.green, size: TtySize.row),
        const SizedBox(width: 10),
        TtyText(
          'Looking for your computer…',
          color: tty.faint,
          size: TtySize.row,
        ),
      ],
    );
  }
}
