import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

import '../tty.dart';
import '../tty_controls.dart';
import 'how_it_works_video.dart';

/// Where the desktop app is downloaded — what "Send link to my Mac" carries. The website's own
/// download page; a shorter `/download` waits on a website release.
const kDesktopDownloadUrl = 'https://harness.autonomous.ai/desktop';

/// The terminal ways, one for each kind of computer.
///
/// [kAppTerminalSetUp] is the same desktop app, installed from a terminal instead of a browser
/// (macOS or Linux). The installer opens the app when it is done, and the app signs in and sets up
/// the rest, so there is nothing to type after it.
const kAppTerminalSetUp = [
  'curl -fsSL https://cdn.autonomous.ai/harness/desktop/install.sh | bash',
];

/// [kCliTerminalSetUp] is the `harness` command alone, for a computer with no desktop (a server,
/// over SSH): install, sign in, start, in the installer's own order.
const kCliTerminalSetUp = [
  'curl -fsSL https://harness.autonomous.ai/cli/install.sh | bash',
  'harness login',
  'harness start',
];

/// **Not yet — set it up**: getting Harness onto the computer, from the phone.
///
/// ```
/// ‹
/// Get Harness for
/// your computer
///
/// Your agents run on your Mac.
///
/// [      Send link to my Mac      ]
///   AirDrop · Messages · Email
///
/// or open on your Mac:
/// harness.autonomous.ai/desktop
///
/// Then open it, and scan the code it shows.
///            Scan to connect
///
/// Using a terminal?
/// The app, on a Mac or Linux:
/// ┌─────────────────────────────────┐
/// │ curl -fsSL https://cdn.auto…    │
/// │                         [ Copy ]│
/// └─────────────────────────────────┘
/// Just the CLI, on a server:
/// ┌─────────────────────────────────┐
/// │ curl -fsSL https://harness…     │
/// │ harness login                   │
/// │ harness start           [ Copy ]│
/// └─────────────────────────────────┘
/// ```
///
/// The app is the way for nearly everyone; the terminal is for the rest, last and small.
class SetUpComputerPage extends StatefulWidget {
  const SetUpComputerPage({
    super.key,
    required this.onScan,
    required this.onBack,
  });

  /// Back to the first screen's other answer, once the app is on the computer.
  final VoidCallback onScan;
  final VoidCallback onBack;

  @override
  State<SetUpComputerPage> createState() => _SetUpComputerPageState();
}

class _SetUpComputerPageState extends State<SetUpComputerPage> {
  /// The block just copied, which says so for two seconds.
  List<String>? _copied;
  Timer? _copiedTimer;
  final _sendKey = GlobalKey();

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  /// The share sheet with the download link: AirDrop straight to the Mac beside you, or Messages
  /// or email to yourself. Anchored to the button for iPad, where the sheet is a popover.
  Future<void> _send() async {
    final box = _sendKey.currentContext?.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        uri: Uri.parse(kDesktopDownloadUrl),
        subject: 'Harness for your computer',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _copy(List<String> lines) {
    unawaited(Clipboard.setData(ClipboardData(text: lines.join('\n'))));
    HapticFeedback.selectionClick();
    _copiedTimer?.cancel();
    setState(() => _copied = lines);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  /// One way to install from a terminal: what it is for, then the lines and their Copy.
  List<Widget> _commands(Tty tty, String label, List<String> lines) => [
    Text(
      label,
      style: tty.style(color: tty.faint, size: TtySize.meta),
    ),
    const SizedBox(height: 6),
    DecoratedBox(
      decoration: BoxDecoration(
        color: ttyRaised(tty),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: SelectableText(
                lines.join('\n'),
                style: tty.style(size: TtySize.meta),
              ),
            ),
            TtyTextButton(
              label: identical(_copied, lines) ? 'Copied' : 'Copy',
              color: identical(_copied, lines) ? tty.green : tty.text,
              onPressed: () => _copy(lines),
            ),
          ],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final tty = Tty.of(context);
    final faint = tty.style(color: tty.faint, size: TtySize.meta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TtyBackButton(onPressed: widget.onBack),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tty.origin, 8, Tty.origin, 24),
            children: [
              Text(
                'Get Harness for\nyour computer',
                style: tty
                    .style(size: TtySize.display, weight: FontWeight.w600)
                    .copyWith(height: 34 / 28, letterSpacing: -0.6),
              ),
              const SizedBox(height: 10),
              Text('Your agents run on your Mac.', style: faint),
              const SizedBox(height: 28),
              KeyedSubtree(
                key: _sendKey,
                child: TtyPrimaryButton(
                  label: 'Send link to my Mac',
                  onPressed: () => unawaited(_send()),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text('AirDrop · Messages · Email', style: faint)),
              const SizedBox(height: 24),
              Text('or open on your Mac:', style: faint),
              const SizedBox(height: 4),
              SelectableText(
                kDesktopDownloadUrl.replaceFirst('https://', ''),
                style: tty.style(size: TtySize.row),
              ),
              const SizedBox(height: 24),
              Text('Then open it, and scan the code it shows.', style: faint),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  // The button's own inset, so its words sit on the gutter.
                  offset: const Offset(-12, 0),
                  child: TtyTextButton(
                    label: 'Scan to connect ›',
                    onPressed: widget.onScan,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text('Using a terminal?', style: tty.style(size: TtySize.row)),
              const SizedBox(height: 12),
              ..._commands(
                tty,
                'The app, on a Mac or Linux:',
                kAppTerminalSetUp,
              ),
              const SizedBox(height: 16),
              ..._commands(
                tty,
                'Just the CLI, on a server:',
                kCliTerminalSetUp,
              ),
              const SizedBox(height: 32),
              // Not at the computer: what it is like, in 30 seconds.
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: TtyTextButton(
                    label: 'See how it works ▶',
                    color: tty.faint,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HowItWorksVideoPage(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
