/// One entry of the web app menu: a workspace command id and its menu label.
/// The command itself lives in the workspace's shared command table.
typedef WebMenuItem = ({String command, String label});

/// A titled group of menu entries.
typedef WebMenuSection = ({String title, List<WebMenuItem> items});

/// What desktop reaches through its native menu bar, for a mouse in a browser.
/// Order follows the native menus: create, open, arrange, then the app itself.
const List<WebMenuSection> kWebMenuSections = [
  (
    title: 'Harness',
    items: [
      (command: 'agent.new', label: 'New harness'),
      (command: 'swarm.new', label: 'New tab'),
      (command: 'harnesses.list', label: 'Agents'),
      (command: 'navigation.needs_input', label: 'Needing input'),
      (command: 'machines.list', label: 'Machines'),
      (command: 'models.list', label: 'Models'),
      (command: 'app.store', label: 'Store'),
    ],
  ),
  (
    title: 'Pane',
    items: [
      (command: 'pane.split_right', label: 'Split right'),
      (command: 'pane.split_down', label: 'Split down'),
      (command: 'pane.zoom', label: 'Zoom pane'),
      (command: 'pane.move_to_tab', label: 'Move pane to tab'),
      (command: 'agent.share', label: 'Share harness'),
      (command: 'pane.close', label: 'Close pane'),
    ],
  ),
  (
    title: 'Workspace',
    items: [
      (command: 'pane.layout', label: 'Layout'),
      (command: 'navigation.history', label: 'History'),
      (command: 'navigation.commands', label: 'All commands'),
    ],
  ),
  (
    title: 'App',
    items: [
      (command: 'app.settings', label: 'Settings'),
      (command: 'app.customize', label: 'Customize'),
      (command: 'app.add_phone', label: 'Add phone'),
      (command: 'keyboard.quick_start', label: 'Quick start'),
      (command: 'keyboard.help', label: 'Keyboard shortcuts'),
    ],
  ),
];

/// The sections as they can be drawn right now: commands that cannot run in
/// this workspace state are left out, and a section left empty goes with them.
List<WebMenuSection> runnableWebMenu(bool Function(String command) canRun) => [
  for (final section in kWebMenuSections)
    if (section.items.where((item) => canRun(item.command)).toList()
        case final items when items.isNotEmpty)
      (title: section.title, items: items),
];
