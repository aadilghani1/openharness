/// Daemons (preview): whether a window without an account has daemons.
///
/// Daemons ship dark (daemons/README.md, "Off switches"). Signed in, the
/// server decides: the window shows them only when `GET /api/zoo` answers 200.
/// Signed out there is no server to ask, so a guest's local zoo stays off, and
/// the window behaves exactly as it did before daemons existed, until the
/// person turns this on in Settings ▸ Account. It is kept on this computer.
library;

import '../notify/alert_sounds.dart' show OnOffPreference;

class DaemonsPreviewStore extends OnOffPreference {
  DaemonsPreviewStore({super.storage}) : super('daemons_preview');
}

/// Loaded at start-up beside the other preferences.
final daemonsPreviewStore = DaemonsPreviewStore();
