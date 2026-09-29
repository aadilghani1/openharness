import 'app_state.dart';
import 'notification_inbox.dart';

/// The macOS menu lists only harnesses with an unread notification.
/// Receipts travel with each row so a menu left open cannot clear newer news.
List<Map<String, Object?>> statusMenuEntries(AppNotifier app) => [
  for (final notification in notificationInbox(app)) _entry(app, notification),
];

Map<String, Object?> _entry(AppNotifier app, InboxNotification notification) {
  final machineId = notification.machineId;
  final agentId = notification.agentId;
  final machine = app.stateOf(machineId);
  final agent = machine?.agents.where((a) => a.id == agentId).firstOrNull;
  final project = agent == null ? null : machine?.projectOf(agent);
  return {
    'machineId': machineId,
    'agentId': agentId,
    'title': notification.title,
    'machineName': machine?.machine.displayName ?? 'Unavailable machine',
    'project': project?.label ?? 'No Project',
    'detail': notification.detail,
    'unavailable': notification.unavailable,
    'unread': true,
    'label': notification.label,
    'readToken': app.agentUnread.readTokenFor(machineId, agentId),
    'questionId': app.questionFor(machineId, agentId)?.requestId,
  };
}

bool statusMenuReceiptIsCurrent(AppNotifier app, Map receipt) {
  final machineId = receipt['machineId'], agentId = receipt['agentId'];
  return machineId is String &&
      agentId is String &&
      receipt['readToken'] ==
          app.agentUnread.readTokenFor(machineId, agentId) &&
      receipt['questionId'] == app.questionFor(machineId, agentId)?.requestId;
}

/// Dismiss the exact notifications displayed when Clear All was selected.
/// A pending question remains pending; a newer notification remains unread.
void clearStatusMenuNotifications(AppNotifier app, List receipts) {
  for (final receipt in receipts.whereType<Map>()) {
    if (receipt['unread'] != true ||
        !statusMenuReceiptIsCurrent(app, receipt)) {
      continue;
    }
    app.readAgentNotification(
      receipt['machineId'] as String,
      receipt['agentId'] as String,
      readToken: receipt['readToken'] as String?,
    );
  }
}
