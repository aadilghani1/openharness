import 'package:flutter/material.dart';

import '../shared/theme/workspace_bar_style.dart';
import '../state/machine_resource_monitor.dart';
import 'workspace_bar_control.dart';

/// Reduce complete metric groups at tight widths; never cut a percentage in half.
class WorkspaceMachineResources extends StatelessWidget {
  const WorkspaceMachineResources({
    super.key,
    required this.monitor,
    this.onPressed,
  });
  final MachineResourceMonitor monitor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final cell = workspaceBarCellSizeOf(context).width;
        var metrics = '';
        for (final candidate in [
          monitor.metricsLabel(),
          monitor.metricsLabel(gpu: false),
        ]) {
          if (workspaceBarTextSizeOf(
                    context,
                    monitor.scopeName + candidate,
                  ).width +
                  cell * 2 <=
              constraints.maxWidth) {
            metrics = candidate;
            break;
          }
        }
        return WorkspaceBarControl(
          label: monitor.detail,
          tooltip: monitor.detail,
          onPressed: onPressed,
          builder: (context, emphasized) => Padding(
            padding: EdgeInsets.symmetric(horizontal: cell),
            child: SizedBox(
              height: workspaceBarControlHeight(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      monitor.scopeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: workspaceBarTextStyle(emphasized: emphasized),
                    ),
                  ),
                  if (metrics.isNotEmpty)
                    Text(
                      metrics,
                      style: workspaceBarTextStyle(emphasized: emphasized),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
