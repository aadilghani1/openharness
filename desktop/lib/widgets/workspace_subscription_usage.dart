/// One shared reading for the Flutter and native workspace footers. The Models
/// controller owns freshness, limiting windows and account deduplication.
class WorkspaceSubscriptionUsage {
  const WorkspaceSubscriptionUsage(this.text, this.detail);

  final String text;
  final String detail;

  factory WorkspaceSubscriptionUsage.fromRows(List<Map<String, Object?>> rows) {
    final accounts = rows
        .where((row) => row['status'] != 'Not signed in')
        .toList();
    final counts = <Object?, int>{};
    for (final row in accounts) {
      counts.update(row['engine'], (count) => count + 1, ifAbsent: () => 1);
    }
    final labels = <String>[];
    final details = <String>['Remaining subscription usage'];
    final positions = <Object?, int>{};
    for (final row in accounts) {
      final engine = row['engine'];
      final provider = switch (engine) {
        'claude' => 'Claude',
        'codex' => 'Codex',
        _ => row['title'] as String? ?? 'Subscription',
      };
      final account = row['account'] as String? ?? '';
      final position = positions.update(
        engine,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      final name = counts[engine]! > 1
          ? '$provider ${account.isEmpty ? position : account}'
          : provider;
      final status = row['status'] as String? ?? 'Usage unavailable';
      final remaining = row['remainingPercent'];
      final figure = remaining is num && remaining.isFinite
          ? status.replaceFirst(RegExp(r' remaining$'), '')
          : '—';
      labels.add('$name $figure');
      details.add(
        '$name${account.isNotEmpty && counts[engine] == 1 ? ' · $account' : ''}: $status',
      );
      final windows = row['details'];
      if (windows is List) details.addAll(windows.whereType<String>());
    }
    return WorkspaceSubscriptionUsage(
      labels.isEmpty ? 'Subscriptions' : labels.join(' · '),
      labels.isEmpty
          ? 'View subscriptions and remaining usage'
          : details.join('\n'),
    );
  }
}
