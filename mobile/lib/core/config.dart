/// Runtime configuration for the phone app.
class AppConfig {
  /// Base URL of the central backend (control plane + ws hub).
  final String apiBaseUrl;
  final String autonomousEnv;

  const AppConfig({required this.apiBaseUrl, this.autonomousEnv = 'prod'});

  /// The production backend, unless a build names another with
  /// `--dart-define=HARNESS_API_URL=…` — a local stack (`http://127.0.0.1:8085` from the simulator),
  /// as the desktop and web builds take the same define.
  static const AppConfig dev = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'HARNESS_API_URL',
      defaultValue: 'https://harness-api.autonomous.ai',
    ),
    autonomousEnv: 'prod',
  );

  /// HTTPS->wss, HTTP->ws for the hub endpoint.
  String get wsBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString().replaceFirst(RegExp(r'/$'), '');
  }
}
