import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/api/api_client.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'tty.dart';
import 'tty_controls.dart';
import 'welcome/connect_code.dart';
import 'welcome/scan_to_connect.dart';

/// What adding a machine from its QR came to.
sealed class AddMachineOutcome {
  const AddMachineOutcome();
}

final class MachineAdded extends AddMachineOutcome {
  const MachineAdded(this.name, {this.browser = false, this.linked = true});
  final String name;

  /// A browser signed in (its QR, `k=v`), rather than a machine added.
  final bool browser;

  /// False: a browser signed in while this phone had no machine to hand it.
  final bool linked;
}

final class AddMachineCancelled extends AddMachineOutcome {
  const AddMachineCancelled();
}

final class AddMachineFailed extends AddMachineOutcome {
  const AddMachineFailed(this.message);
  final String message;
}

/// A machine's QR — `harness link qr`, or Add Phone in the desktop app — to a linked machine:
///
/// 1. the code must be for a machine, on this account;
/// 2. **Add this machine?** — its name, whether it is up, its fingerprint to compare with its screen;
/// 3. the one-time-code pairing, refusing a machine whose key is not the fingerprint the QR named;
/// 4. the trust group then brings it to every other machine ([AppNotifier.connectWithCode] syncs).
///
/// [onStatus] hears "Pairing…" and the like, for a page that shows progress inline.
Future<AddMachineOutcome> addMachineFromCode(
  BuildContext context,
  AppNotifier notifier,
  ConnectCode code, {
  void Function(String status)? onStatus,
}) async {
  if (code.isViewerSignIn) {
    return _approveBrowser(context, notifier, code, onStatus: onStatus);
  }
  if (code.isSignIn) {
    return _approveSignIn(context, notifier, code, onStatus: onStatus);
  }
  final machineId = code.machineId, pairCode = code.pairCode;
  if (machineId == null || pairCode == null) {
    return const AddMachineFailed(
      "That code can't add a machine. On the machine, run `harness link qr` "
      '(or Harness ▸ Add Phone… in the desktop app) and scan that.',
    );
  }
  final me = notifier.currentUser?.email;
  if (me != null &&
      code.email.isNotEmpty &&
      code.email.toLowerCase() != me.toLowerCase()) {
    return AddMachineFailed(
      'That machine is signed in as ${code.email}, not $me. '
      'Sign in to Harness on it with $me first.',
    );
  }
  if (!notifier.machineStates.containsKey(machineId)) {
    onStatus?.call('Looking for it on your account…');
    try {
      await notifier.refreshMachines().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } catch (_) {
      return const AddMachineFailed(
        "Couldn't reach your account. Check your connection and scan again.",
      );
    }
  }
  if (!context.mounted) return const AddMachineCancelled();
  final state = notifier.machineStates[machineId];
  if (state == null) {
    return AddMachineFailed(
      "That machine isn't on your account. Sign in to Harness on it "
      'with ${me ?? 'this account'}.',
    );
  }
  final approved = await Navigator.of(context).push<ConfirmAnswer>(
    // A page that answers: the same slide as phoneRoute, typed for the yes/no.
    CupertinoPageRoute<ConfirmAnswer>(
      builder: (route) => ConfirmMachinePage(
        name: state.machine.displayName,
        hostname: code.hostname,
        online: state.nodeOnline,
        fingerprint: code.fingerprint,
        email: me,
        otherMachines: notifier.machineStates.values
            .where((s) => s.machine.machineId != machineId && !s.needsLink)
            .length,
      ),
    ),
  );
  if (approved != ConfirmAnswer.approve) return const AddMachineCancelled();
  onStatus?.call('Pairing…');
  final error = await notifier.connectWithCode(
    machineId,
    pairCode,
    expectedFingerprint: code.fingerprint,
  );
  if (error != null) return AddMachineFailed(error);
  return MachineAdded(state.machine.displayName);
}

/// A machine that is not signed in yet (`harness login`'s QR): this phone signs it in to its own
/// account and takes it into its trust group — the approval is the whole exchange.
Future<AddMachineOutcome> _approveSignIn(
  BuildContext context,
  AppNotifier notifier,
  ConnectCode code, {
  void Function(String status)? onStatus,
}) async {
  final request = code.signInRequest!, pairCode = code.pairCode;
  if (pairCode == null) {
    return const AddMachineFailed(
      "That code can't add a machine. Scan the one `harness login` shows.",
    );
  }
  onStatus?.call('Reading the code…');
  final MachineSignInRequest asking;
  try {
    asking = await notifier.api.lookupMachineSignIn(request);
  } catch (_) {
    return const AddMachineFailed(
      "That code expired or was already used. Scan the machine's new one.",
    );
  }
  // The server's copy of the fingerprint must be the QR's: otherwise the code on the screen is not
  // the request being approved.
  final qrFp = code.fingerprint;
  if (qrFp != null &&
      asking.fingerprint != null &&
      !_sameFingerprint(qrFp, asking.fingerprint!)) {
    return const AddMachineFailed(
      "That code doesn't match the machine's sign-in request. Nothing was approved.",
    );
  }
  if (!context.mounted) return const AddMachineCancelled();
  final answer = await Navigator.of(context).push<ConfirmAnswer>(
    CupertinoPageRoute<ConfirmAnswer>(
      builder: (route) => ConfirmMachinePage(
        name: code.hostname ?? asking.label,
        fingerprint: qrFp ?? asking.fingerprint,
        email: notifier.currentUser?.email,
        country: asking.country,
        signIn: true,
        otherMachines: notifier.machineStates.values
            .where((s) => !s.needsLink)
            .length,
      ),
    ),
  );
  if (answer == ConfirmAnswer.notMe) {
    try {
      await notifier.api.denyMachineSignIn(request);
    } catch (_) {
      // The request dies in minutes anyway.
    }
    return const AddMachineFailed('Declined. That machine was not signed in.');
  }
  if (answer != ConfirmAnswer.approve) return const AddMachineCancelled();
  final pub = asking.pub;
  if (pub == null) {
    return const AddMachineFailed(
      'That machine runs an older Harness. Update it (harness update) and scan again.',
    );
  }
  // The approval is the whole exchange: this phone checks the machine's key against the QR, signs it
  // in, takes it into its group and hands it the group's keys (sealed under the QR's code). Neither
  // dials the other; the group sync spreads the rest in the background.
  onStatus?.call('Signing it in and adding it to your devices…');
  final name = code.hostname ?? asking.label;
  final out = await notifier.approveSignInByQr(
    userCode: request,
    code: pairCode,
    pub: pub,
    label: name,
    qrFingerprint: qrFp,
    machine: true,
  );
  if (out.error == 'FINGERPRINT') {
    return const AddMachineFailed(
      "That machine's key doesn't match its code. Nothing was approved.",
    );
  }
  if (out.error != null) {
    return const AddMachineFailed(
      "Couldn't approve it — the code may have expired. Scan the machine's new one.",
    );
  }
  return MachineAdded(name);
}

/// A BROWSER asking to be signed in (the web sign-in page's QR, `k=v`): this phone signs it in to
/// its own account and takes it into its trust group — the browser gets this phone's roster, sealed
/// under the QR's code, and the machines hear of the browser from this phone's sync. No machine has
/// to be dialled for the browser first.
Future<AddMachineOutcome> _approveBrowser(
  BuildContext context,
  AppNotifier notifier,
  ConnectCode code, {
  void Function(String status)? onStatus,
}) async {
  final request = code.signInRequest!, pairCode = code.pairCode;
  if (pairCode == null) {
    return const AddMachineFailed(
      "That code can't sign a browser in. Scan the one its sign-in page shows.",
    );
  }
  onStatus?.call('Reading the code…');
  final MachineSignInRequest asking;
  try {
    asking = await notifier.api.lookupMachineSignIn(request);
  } catch (_) {
    return const AddMachineFailed(
      'That code expired or was already used. Scan the new one on the browser.',
    );
  }
  final pub = asking.pub;
  if (pub == null) {
    return const AddMachineFailed(
      "That browser's sign-in page is too old to be added. Reload it and scan again.",
    );
  }
  if (!context.mounted) return const AddMachineCancelled();
  final name = asking.label;
  final answer = await Navigator.of(context).push<ConfirmAnswer>(
    CupertinoPageRoute<ConfirmAnswer>(
      builder: (route) => ConfirmMachinePage(
        name: name,
        fingerprint: code.fingerprint ?? asking.fingerprint,
        email: notifier.currentUser?.email,
        country: asking.country,
        signIn: true,
        browser: true,
      ),
    ),
  );
  if (answer == ConfirmAnswer.notMe) {
    try {
      await notifier.api.denyMachineSignIn(request);
    } catch (_) {}
    return const AddMachineFailed('Declined. That browser was not signed in.');
  }
  if (answer != ConfirmAnswer.approve) return const AddMachineCancelled();
  onStatus?.call('Signing it in and adding it to your devices…');
  final out = await notifier.approveSignInByQr(
    userCode: request,
    code: pairCode,
    pub: pub,
    label: name,
    qrFingerprint: code.fingerprint,
  );
  if (out.error == 'FINGERPRINT') {
    return const AddMachineFailed(
      "That browser's key doesn't match its code. Nothing was approved.",
    );
  }
  if (out.error != null) {
    return const AddMachineFailed(
      "Couldn't approve it — the code may have expired. Scan the new one.",
    );
  }
  return MachineAdded(name, browser: true, linked: out.machines > 0);
}

bool _sameFingerprint(String a, String b) {
  String norm(String v) => v.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
  return norm(a) == norm(b);
}

/// Stands in for the camera behind every "Scan a QR code" door, in tests — which cannot open one.
@visibleForTesting
Widget? debugScanCamera;

/// **Scan a QR code** — the camera (or a pasted `…/pair#…` link), then whatever the code asks:
/// a browser or a machine signing in is approved and taken into this phone's group; a machine
/// already signed in (`harness link qr`) is linked. The outcome is said in a snackbar.
Future<void> scanToApprove(
  BuildContext context,
  AppNotifier notifier, {
  Widget? camera,
  Future<String?> Function()? readClipboard,
}) async {
  final code = await scanForCode(
    context,
    fallbackLabel: 'Not now',
    camera: camera ?? debugScanCamera,
    title: 'Scan the QR on the computer or browser signing in',
    hint: '`harness login`, the desktop app, or Harness on the web',
    allowPaste: true,
    readClipboard: readClipboard,
  );
  if (code == null || !context.mounted) return;
  final outcome = await addMachineFromCode(context, notifier, code);
  if (!context.mounted) return;
  final message = switch (outcome) {
    MachineAdded(:final name, browser: true, linked: false) =>
      '$name is signed in. Machines you link later reach it too.',
    MachineAdded(:final name, browser: true) =>
      '$name is signed in and reaches your machines.',
    MachineAdded(:final name) =>
      '$name added — it reaches your other machines, and they reach it.',
    AddMachineFailed(:final message) => message,
    AddMachineCancelled() => null,
  };
  if (message == null) return;
  HapticFeedback.mediumImpact();
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

/// **Add this machine?** — what the scanned QR says, before anything is paired.
///
/// ```
/// Add this machine?
/// machine-remote-2 · online
/// Fingerprint  5F80·61C4·6142·ADCF
/// Check it matches the machine's screen.
/// Account  dee@autonomous.ai
/// It will reach, and be reached by, your 3 other machines.
///                                   [ Approve ]   Cancel
/// ```
/// What the person chose on [ConfirmMachinePage].
enum ConfirmAnswer { approve, cancel, notMe }

class ConfirmMachinePage extends StatelessWidget {
  const ConfirmMachinePage({
    super.key,
    required this.name,
    this.hostname,
    this.online,
    this.fingerprint,
    this.email,
    this.otherMachines = 0,
    this.signIn = false,
    this.country,
    this.browser = false,
  });

  /// A browser asking to be signed in (`k=v`), not a machine.
  final bool browser;

  /// A machine asking to be signed in (`harness login`): approving signs it in to this account.
  final bool signIn;

  /// Where that request came from, when the relay could tell.
  final String? country;

  final String name;
  final String? hostname;
  final bool? online;
  final String? fingerprint;
  final String? email;
  final int otherMachines;

  /// `5F8061C46142ADCF` as the machine prints it: `5F80·61C4·6142·ADCF`.
  static String spaced(String fingerprint) {
    final plain = fingerprint.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    final groups = <String>[];
    for (var i = 0; i < plain.length; i += 4) {
      groups.add(
        plain.substring(i, i + 4 > plain.length ? plain.length : i + 4),
      );
    }
    return groups.join('·');
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final tty = Tty.of(context);
    final status = switch (online) {
      true => ('online', tty.green),
      false => ('offline — start Harness on it', tty.yellow),
      null => ('status unknown', tty.faint),
    };
    final shownHost = hostname != null && hostname != name ? hostname : null;
    final String reach;
    if (browser) {
      reach = 'It joins your devices and reaches your machines — no password.';
    } else {
      reach = otherMachines == 0
          ? 'This phone will reach it without a password.'
          : 'It will reach, and be reached by, your $otherMachines other '
                'machine${otherMachines == 1 ? '' : 's'} — no password.';
    }
    return Scaffold(
      backgroundColor: tty.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tty.origin, 24, Tty.origin, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TtyBackButton(
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                browser
                    ? 'Sign in this browser?'
                    : signIn
                    ? 'Sign in & add machine?'
                    : 'Add this machine?',
                style: tty
                    .style(size: TtySize.display, weight: FontWeight.w600)
                    .copyWith(height: 34 / 28, letterSpacing: -0.6),
              ),
              const SizedBox(height: 20),
              TtyText(name, size: TtySize.row, weight: FontWeight.w600),
              if (shownHost != null)
                TtyText(shownHost, color: tty.faint, size: TtySize.meta),
              if (!browser)
                TtyText(status.$1, color: status.$2, size: TtySize.meta),
              const SizedBox(height: 20),
              if (fingerprint != null) ...[
                TtyText('Fingerprint', color: tty.faint, size: TtySize.meta),
                TtyText(
                  spaced(fingerprint!),
                  size: TtySize.row,
                  weight: FontWeight.w600,
                ),
                TtyText(
                  browser
                      ? "Check it matches the browser's screen."
                      : "Check it matches the machine's screen.",
                  color: tty.faint,
                  size: TtySize.meta,
                ),
                const SizedBox(height: 20),
              ],
              if (email != null) ...[
                TtyText(
                  signIn ? 'It will sign in as' : 'Account',
                  color: tty.faint,
                  size: TtySize.meta,
                ),
                TtyText(email!, size: TtySize.row),
                const SizedBox(height: 20),
              ],
              if (signIn) ...[
                if (country != null)
                  TtyText(
                    'Requested from $country',
                    color: tty.faint,
                    size: TtySize.meta,
                  ),
                TtyText(
                  browser
                      ? 'Only approve a browser you are using right now — '
                            'it gets your account and your machines.'
                      : 'Only approve a machine you are setting up right now.',
                  color: tty.yellow,
                  size: TtySize.meta,
                ),
                const SizedBox(height: 20),
              ],
              TtyText(reach, color: tty.faint, size: TtySize.meta),
              const Spacer(),
              TtyPrimaryButton(
                label: 'Approve',
                onPressed: () =>
                    Navigator.of(context).pop(ConfirmAnswer.approve),
              ),
              const SizedBox(height: 8),
              Center(
                child: TtyTextButton(
                  label: 'Cancel',
                  onPressed: () =>
                      Navigator.of(context).pop(ConfirmAnswer.cancel),
                ),
              ),
              if (signIn)
                Center(
                  child: TtyTextButton(
                    label: 'Not me',
                    color: tty.red,
                    onPressed: () =>
                        Navigator.of(context).pop(ConfirmAnswer.notMe),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
