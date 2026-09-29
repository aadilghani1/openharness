import '../../state/app_state.dart';
import '../../state/workspace_chrome.dart';
import '../picker/web_picker_bar.dart';
import 'web_app_menu.dart';
import 'web_machine_choice.dart';

/// Everything the browser adds to the shared workspace: a menu before the
/// tabs, a clickable bar over the picker with its key hints hidden, and a
/// connected machine for New Harness, since a browser is not a machine.
WorkspaceChrome webWorkspaceChrome(AppNotifier app) => WorkspaceChrome(
  leadingWidth: WebAppMenuButton.widthOf,
  leading: (context, commands) =>
      WebAppMenuButton(app: app, commands: commands),
  newHarnessMachine: () => webNewHarnessMachine(app),
  pickerBar: (context, picker) => WebPickerBar(picker: picker),
  showsKeyHints: false,
);
