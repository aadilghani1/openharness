import 'package:web/web.dart' as web;

import 'local_key_value_store.dart';

/// The browser adapter behind the same state-store entry point as desktop.
/// Preferences persist per origin; sign-in and machine keys stay in this tab's
/// session storage, surviving reloads without sharing rotating tokens across
/// independently running tabs. Storage errors propagate for credential writes.
class HarnessFileStore implements BatchLocalKeyValueStore {
  static final HarnessFileStore shared = HarnessFileStore();
  static const _prefix = 'harness.web.v1.';

  web.Storage _storage(String key) =>
      key.startsWith('auth_') || key.startsWith('viewer_e2ee_')
      ? web.window.sessionStorage
      : web.window.localStorage;

  @override
  Future<String?> read(String key) async =>
      _storage(key).getItem('$_prefix$key');

  @override
  Future<Map<String, String?>> readMany(Iterable<String> keys) async => {
    for (final key in keys) key: _storage(key).getItem('$_prefix$key'),
  };

  @override
  Future<void> write(String key, String value) async =>
      _storage(key).setItem('$_prefix$key', value);

  @override
  Future<void> delete(String key) async =>
      _storage(key).removeItem('$_prefix$key');

  /// Native-only services must never turn a browser path into a local file.
  static String defaultDirectoryPath({
    Map<String, String>? environment,
    String? name,
  }) => throw UnsupportedError('The browser has no Harness home directory.');
}
