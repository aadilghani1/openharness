import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/setting_row.dart';
import '../experimental_features.dart';

class ExperimentalSection extends StatelessWidget {
  const ExperimentalSection({super.key, this.store});

  final ExperimentalFeaturesStore? store;

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
    final preferences = store ?? experimentalFeaturesStore;
    final features = ExperimentalFeature.values.where((f) => f.available);
    return SectionScaffold(
      title: 'Experimental',
      subtitle:
          'Try features that are still taking shape. Turn them off any time.',
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: preferences,
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
            ],
          ),
        ),
      ),
    );
  }
}
