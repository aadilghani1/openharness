import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';
import '../core/viewer_mode.dart';

/// The catalog behind Settings → Experimental. Add new opt-in features here
/// so their labels, storage keys and switches stay together.
enum ExperimentalFeature {
  focusBarCreature(
    'focus_bar_creature',
    'Focus-bar creature',
    'Start with an egg in the focus bar. Work toward hatching your companion. '
        'Its test collection resets when you close the window.',
  ),
  shareButton(
    'share_button',
    'Share button',
    'Show Share in the top-right corner of the workspace.',
  );

  const ExperimentalFeature(this.id, this.label, this.description);
  final String id, label, description;

  String get storageKey => 'experimental.$id';

  bool get available => switch (this) {
    // The creature preview belongs to the native desktop workspace.
    focusBarCreature => !kIsWeb && !kViewerMode,
    shareButton => true,
  };
}

/// Per-installation preferences, loaded before the first frame. Experiments are
/// off until chosen; neither an account nor a server can opt a user into one.
class ExperimentalFeaturesStore extends ChangeNotifier {
  ExperimentalFeaturesStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared;

  final LocalKeyValueStore _storage;
  final _choices = <ExperimentalFeature, bool>{};
  final _edits = <ExperimentalFeature, int>{};
  Future<void>? _saving;
  bool _disposed = false;

  bool enabled(ExperimentalFeature feature) => choice(feature) == true;

  /// Null means no local choice. This lets the creature preserve the separate
  /// account rollout until a person explicitly overrides it with this preview.
  bool? choice(ExperimentalFeature feature) => _choices[feature];

  Future<void> load() async {
    final edits = Map.of(_edits);
    try {
      final values = await _storage.readMany(
        ExperimentalFeature.values.map((feature) => feature.storageKey),
      );
      if (_disposed) return;
      var changed = false;
      for (final feature in ExperimentalFeature.values) {
        if (_edits[feature] != edits[feature]) continue;
        final value = switch (values[feature.storageKey]) {
          'on' => true,
          'off' => false,
          _ => null,
        };
        if (choice(feature) == value) continue;
        changed = true;
        if (value == null) {
          _choices.remove(feature);
        } else {
          _choices[feature] = value;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {
      // Missing or unreadable preferences never opt someone into an experiment.
    }
  }

  /// Apply immediately and serialize writes so the last flip wins. A failed
  /// save is reported to the caller and does not poison later writes or retries.
  Future<void> set(ExperimentalFeature feature, bool on) {
    _edits[feature] = (_edits[feature] ?? 0) + 1;
    final changed = choice(feature) != on;
    _choices[feature] = on;
    if (changed && !_disposed) notifyListeners();
    final pending = (_saving ?? Future<void>.value()).then(
      (_) => _storage.write(feature.storageKey, on ? 'on' : 'off'),
    );
    _saving = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final experimentalFeaturesStore = ExperimentalFeaturesStore();
