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
    final status = state.saving
        ? 'Saving…'
        : !state.loaded && state.error == null
        ? 'Loading…'
        : null;
    return SettingRow(
      title: 'Swarm collaboration',
      detail:
          'Let agents automatically consult only peers in the same tab. '
          'Off by default. This setting applies to your account.',
      control: Semantics(
        label: 'Swarm collaboration',
        child: Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            key: const Key('experimental-swarm-collaboration'),
            value: state.enabled,
            onChanged: state.loaded && !state.saving
                ? (on) => unawaited(state.setEnabled(on))
                : null,
          ),
        ),
      ),
      footer: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use “Swarm conversation” in the command palette to inspect '
              'their questions and replies.',
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(status)),
            ],
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(error)),
              TextButton(
                onPressed: state.saving
                    ? null
                    : () => unawaited(state.refresh()),
                child: const Text('Refresh setting'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
