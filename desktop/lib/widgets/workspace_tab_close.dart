import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/workspace_bar_style.dart';

/// Cells a tab reserves for its close mark, so hovering never reflows the row.
const int kWorkspaceTabCloseCells = 2;

/// A tab's label with a close mark after it, for hosts that close tabs by
/// mouse ([WorkspaceChrome.closesTabs]). The mark keeps its cells while
/// hidden and only shows on the selected or hovered tab, as browser tabs do.
class WorkspaceTabCloseSlot extends StatelessWidget {
  const WorkspaceTabCloseSlot({
    super.key,
    required this.tabId,
    required this.visible,
    required this.color,
    required this.onClose,
    required this.child,
  });

  final String tabId;
  final bool visible;
  final Color color;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width =
        workspaceBarCellSizeOf(context).width * kWorkspaceTabCloseCells;
    return Row(
      children: [
        Expanded(child: child),
        SizedBox(
          width: width,
          child: !visible
              ? null
              : Tooltip(
                  message: 'Close tab',
                  waitDuration: const Duration(milliseconds: 700),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    // Inside the tab's own tap target: the innermost detector
                    // wins the tap, so this closes without selecting first.
                    child: GestureDetector(
                      key: ValueKey('tab-close:$tabId'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: Icon(LucideIcons.x, size: 13, color: color),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
