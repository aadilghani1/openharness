import 'package:flutter/material.dart';

import '../shared/theme/app_icons.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'harness_agent_picker.dart';

/// The agent name, immediately beside the model, opens the shared & picker.
class HarnessAgentControl extends StatelessWidget {
  const HarnessAgentControl({
    super.key,
    required this.app,
    required this.machineId,
    required this.agent,
    this.enabled = true,
  });
  final AppNotifier app;
  final String machineId;
  final Agent agent;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Change agent',
    child: TextButton(
      key: const ValueKey('pane-agent-control'),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      ),
      onPressed: !enabled || app.openAgentPicker == null
          ? null
          : () => app.openAgentPicker!(machineId, agent.id),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              HarnessAgentPicker.label(agent.engine ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(AppIcons.chevronDown, size: 12),
        ],
      ),
    ),
  );
}
