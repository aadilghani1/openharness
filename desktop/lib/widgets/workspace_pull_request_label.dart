import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/theme/pull_request_icon.dart';
import '../shared/theme/workspace_bar_style.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';

/// The state icon and number are one link, without a second status word or a
/// filled badge. The enclosing control supplies the full state and action.
class WorkspacePullRequestLabel extends StatelessWidget {
  const WorkspacePullRequestLabel({
    super.key,
    required this.number,
    required this.state,
    this.color = true,
    this.emphasized = false,
  });

  final int number;
  final String state;
  final bool color;
  final bool emphasized;

  static double widthOf(BuildContext context, int number) =>
      MediaQuery.textScalerOf(context).scale(workspaceBarFontSize) +
      workspaceBarCellSizeOf(context).width +
      workspaceBarTextSizeOf(context, '#$number').width;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder(
      valueListenable: terminalThemeStore,
      builder: (context, _, _) {
        final theme = terminalThemeFor(
          grid.AppTheme.palette.value,
          terminalThemeStore.value,
        );
        final iconSize = MediaQuery.textScalerOf(context)
            .scale(workspaceBarFontSize);
        final gap = workspaceBarCellSizeOf(context).width;
        return Semantics(
          label: 'Pull request #$number: $state',
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(
                  widthOf(context, number),
                  constraints.maxWidth,
                );
                final icon = SvgPicture.asset(
                  pullRequestIconAsset(state),
                  width: iconSize,
                  height: iconSize,
                  colorFilter: ColorFilter.mode(
                    pullRequestIconColor(state, theme, color: color),
                    BlendMode.srcIn,
                  ),
                );
                return SizedBox(
                  width: width,
                  height: workspaceBarControlHeight(context),
                  child: width < iconSize + gap
                      ? ClipRect(child: Center(child: icon))
                      : Row(
                          children: [
                            icon,
                            SizedBox(width: gap),
                            Expanded(
                              child: Text(
                                '#$number',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: workspaceBarTextStyle(
                                  color: theme.foreground,
                                  emphasized: emphasized,
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
