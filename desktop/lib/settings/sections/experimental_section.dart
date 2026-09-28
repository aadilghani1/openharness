import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/setting_row.dart';
import '../../teams/swarm_settings_controller.dart';

class ExperimentalSection extends StatefulWidget {
  const ExperimentalSection({super.key, required this.controller});
  final SwarmSettingsController controller;

  @override
  State<ExperimentalSection> createState() => _ExperimentalSectionState();
}

class _ExperimentalSectionState extends State<ExperimentalSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) => SectionScaffold(
    title: 'Experimental',
    subtitle:
        'Try features that are still taking shape. Turn them off any time.',
    child: SingleChildScrollView(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final state = widget.controller;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MergeSemantics(
                child: SettingRow(
                  title: 'Swarm collaboration',
                  detail:
                      'Let agents in the same tab automatically consult each other. '
                      'Off by default. This setting applies to your account.',
                  control: SizedBox(
                    width: SettingRow.controlWidth,
                    child: Row(
                      children: [
                        Switch(
                          key: const Key('experimental-swarm-collaboration'),
                          value: state.enabled,
                          onChanged: state.loaded && !state.saving
                              ? (on) => unawaited(state.setEnabled(on))
                              : null,
                        ),
                        Flexible(
                          child: Text(
                            state.saving
                                ? 'Saving…'
                                : !state.loaded
                                ? state.error == null
                                      ? 'Loading…'
                                      : 'Unavailable'
                                : state.enabled
                                ? 'On'
                                : 'Off',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Agents stay within their tab unless you explicitly ask for help from another swarm. '
                'Use “Swarm conversation” in the command palette to inspect their questions and replies.',
              ),
              if (state.error case final error?) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(error)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: state.saving
                        ? null
                        : () => unawaited(state.refresh()),
                    child: const Text('Refresh setting'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
