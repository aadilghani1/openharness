import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/setting_row.dart';
import '../experimental_features.dart';
import '../../teams/swarm_settings_controller.dart';

class ExperimentalSection extends StatefulWidget {
  const ExperimentalSection({super.key, this.store, this.controller});

  final ExperimentalFeaturesStore? store;
  final SwarmSettingsController? controller;

  @override
  State<ExperimentalSection> createState() => _ExperimentalSectionState();
}

class _ExperimentalSectionState extends State<ExperimentalSection> {
  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    if (controller != null) unawaited(controller.refresh());
  }

  Future<void> _set(
    BuildContext context,
    ExperimentalFeaturesStore preferences,
    ExperimentalFeature feature,
    bool on,
  ) async {
    try {
      await preferences.set(feature, on);
    } catch (_) {
      if (!context.mounted || preferences.enabled(feature) != on) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'This change couldn’t be saved. It will last for this window.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(
              _set(context, preferences, feature, preferences.enabled(feature)),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.store ?? experimentalFeaturesStore;
    final features = ExperimentalFeature.values.where((f) => f.available);
    return SectionScaffold(
      title: 'Experimental',
      subtitle:
          'Try features that are still taking shape. Turn them off any time.',
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: Listenable.merge([preferences, widget.controller]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              for (final feature in features)
                MergeSemantics(
                  child: SettingRow(
                    title: feature.label,
                    detail: feature.description,
                    control: Align(
                      alignment: Alignment.centerLeft,
                      child: Switch(
                        key: ValueKey('experimental-${feature.id}'),
                        value: preferences.enabled(feature),
                        onChanged: (on) =>
                            unawaited(_set(context, preferences, feature, on)),
                      ),
                    ),
                  ),
                ),
              if (widget.controller case final controller?)
                _SwarmCollaborationSetting(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwarmCollaborationSetting extends StatelessWidget {
  const _SwarmCollaborationSetting({required this.controller});
  final SwarmSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller;
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
          'Agents consult only peers in their tab. '
          'Use “Swarm conversation” in the command palette to inspect their questions and replies.',
        ),
        if (state.error case final error?) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(error)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: state.saving ? null : () => unawaited(state.refresh()),
              child: const Text('Refresh setting'),
            ),
          ),
        ],
      ],
    );
  }
}
