import 'dart:async';

import 'package:flutter/material.dart';

import '../../daemons/daemons_preview.dart';
import '../../screens/login_screen.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/setting_row.dart';
import '../../state/app_state.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key, required this.notifier, this.previewStore});

  final AppNotifier notifier;

  /// Injected by tests; the app reads the one loaded at start-up.
  final DaemonsPreviewStore? previewStore;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      final local = notifier.localManualFixture != null;
      final profile = notifier.currentUser;
      // A guest's row says what an account is FOR and offers it; the sheet opens
      // over Settings, which stays where it is — there is nothing to leave, and
      // the row rewrites itself the moment the account arrives.
      if (notifier.isGuest) {
        return SectionScaffold(
          title: 'Account',
          subtitle:
              'This computer works without one. An account adds your other '
              'machines, the shared desk and voice on the dial.',
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingRow(
                  title: 'Not signed in',
                  detail: 'Sign in to reach your other machines',
                  control: FilledButton(
                    key: const Key('settings-sign-in-button'),
                    // Straight back to the desk once the account lands.
                    // Settings is where the person WENT to sign in, not where
                    // they were going: leaving them on a row that now just
                    // says their email is the app asking them to find their
                    // own way out (owner, 2026-09-23). Sign out is the same
                    // shape, in reverse.
                    onPressed: () async {
                      final signedIn = await showSignInSheet(context, notifier);
                      if (signedIn && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 10),
                // Signed out there is no server to say whether this computer
                // has daemons: they stay off until the person asks for them.
                ValueListenableBuilder<bool>(
                  valueListenable: previewStore ?? daemonsPreviewStore,
                  builder: (context, on, _) => SettingRow(
                    title: 'Daemons (preview)',
                    detail:
                        'A daemon in the status line that hatches from your '
                        'work and watches your harnesses. Kept on this '
                        'computer.',
                    control: Align(
                      alignment: Alignment.centerLeft,
                      child: Switch(
                        key: const Key('settings-daemons-preview'),
                        value: on,
                        onChanged: (next) => unawaited(
                          (previewStore ?? daemonsPreviewStore).set(next),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return SectionScaffold(
        title: 'Account',
        subtitle: local
            ? 'Connected to a local development session.'
            : 'Your Harness sign-in on this computer.',
        child: SingleChildScrollView(
          child: SettingRow(
            title:
                profile?.displayName ?? (local ? 'Local session' : 'Signed in'),
            detail:
                profile?.email ??
                (local ? 'Loopback backend' : 'Profile unavailable'),
            control: OutlinedButton(
              key: const Key('settings-sign-out-button'),
              onPressed: () {
                Navigator.of(context).pop();
                notifier.logout();
              },
              child: Text(local ? 'Disconnect local session' : 'Sign out'),
            ),
          ),
        ),
      );
    },
  );
}
