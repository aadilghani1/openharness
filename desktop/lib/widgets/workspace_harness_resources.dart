import 'package:flutter/material.dart';

import '../shared/theme/workspace_bar_style.dart';
import '../state/harness_monitor.dart';
import 'workspace_bar_control.dart';

/// Every resource opens the same monitor. Hide whole groups at narrow widths.
class WorkspaceHarnessResources extends StatelessWidget {
  const WorkspaceHarnessResources({
    super.key,
    required this.monitor,
    this.onPressed,
  });
  final HarnessMonitor monitor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final cell = workspaceBarCellSizeOf(context).width;
        var label = monitor.metricsLabel(
          ram: false,
          gpu: false,
          storage: false,
        );
        for (final candidate in [
          monitor.metricsLabel(),
          monitor.metricsLabel(storage: false),
          monitor.metricsLabel(gpu: false, storage: false),
        ]) {
          if (workspaceBarTextSizeOf(context, candidate, grouped: true).width +
                  cell * 2 <=
              constraints.maxWidth) {
            label = candidate;
            break;
          }
        }
        return WorkspaceBarControl(
          label: monitor.resourceDetail,
          tooltip: monitor.resourceDetail,
          onPressed: onPressed,
          builder: (context, emphasized) => Padding(
            padding: EdgeInsets.symmetric(horizontal: cell),
            child: SizedBox(
              height: workspaceBarControlHeight(context),
              child: Center(
                widthFactor: 1,
                child: Text.rich(
                  workspaceBarGroupTextSpan(label, cellWidth: cell),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: workspaceBarTextStyle(emphasized: emphasized),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
