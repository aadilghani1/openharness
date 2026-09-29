import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shortcuts/keymap_commands.dart';
import 'package:harness/web/shell/web_menu_items.dart';

void main() {
  test('every web menu row names a registered workspace command', () {
    final registered = {for (final command in harnessCommands) command.id};
    for (final section in kWebMenuSections) {
      for (final item in section.items) {
        expect(registered, contains(item.command), reason: item.label);
      }
    }
  });

  test('rows that cannot run, and sections left empty, are not drawn', () {
    final menu = runnableWebMenu(
      (command) => !command.startsWith('pane.') && command != 'agent.share',
    );
    final titles = [for (final section in menu) section.title];
    expect(titles, isNot(contains('Pane')));
    final workspace = menu.firstWhere((s) => s.title == 'Workspace');
    expect(workspace.items.map((i) => i.command), [
      'navigation.history',
      'navigation.commands',
    ]);
    expect(runnableWebMenu((_) => false), isEmpty);
  });
}
