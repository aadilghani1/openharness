import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'password_link.dart' show RelaySocketFactory;

/// The account's own socket: `/api/web-ws` with this device's session and no machine selected — the
/// line the backend's account-wide pushes arrive on (`group_changed`, `machines_changed`), even on a
/// device that has no machine linked yet and so no machine socket to hear them through.
///
/// Every frame here is a HINT to re-read something over REST. It carries nothing trusted: a device
/// believes a group change only from signatures on the board (`group_sync.dart` `acceptVouches`).
///
/// Reconnects with backoff (1 s doubling to 30 s, reset by a socket that stayed up [_stable]) until
/// [close]. A token that cannot be had (signed out) waits the same way. A push sent while the socket
/// was down reached nobody, so every reconnect after the first reports each watched type once — the
/// caller re-reads, and an unchanged revision costs one small GET.
class AccountEvents {
  AccountEvents({
    required this.token,
    required this.uri,
    required this.socket,
    required this.onEvent,
  });

  final Future<String> Function() token;
  final Uri uri;
  final RelaySocketFactory socket;

  /// A frame's type and payload, for the types this socket is for.
  final void Function(String type, Map<String, dynamic> payload) onEvent;

  static const _watched = {'group_changed', 'machines_changed'};
  static const _maxBackoff = Duration(seconds: 30);

  /// An unselected socket never hears `connected` (that answers `machine_select`), so staying up this
  /// long is what proves a dial good.
  static const _stable = Duration(seconds: 30);

  WebSocketChannel? _channel;
  Timer? _retry;
  bool _closed = false;
  bool _started = false;
  int _attempt = 0;
  bool _everOpen = false;
  DateTime? _openedAt;

  void start() {
    if (_started || _closed) return;
    _started = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed) return;
    final String credential;
    try {
      credential = await token();
    } catch (_) {
      return _later();
    }
    if (_closed) return;
    final WebSocketChannel ch;
    try {
      ch = _channel = socket(uri, [credential]);
      await ch.ready;
    } catch (_) {
      return _later();
    }
    if (_closed) {
      unawaited(ch.sink.close());
      return;
    }
    _openedAt = DateTime.now();
    if (_everOpen) {
      for (final type in _watched) {
        onEvent(type, const {});
      }
    }
    _everOpen = true;
    ch.stream.listen(
      (raw) {
        if (raw is! String) return;
        final Object? frame;
        try {
          frame = jsonDecode(raw);
        } on FormatException {
          return;
        }
        if (frame is! Map) return;
        final type = frame['type'];
        if (type is String && _watched.contains(type)) {
          final payload = frame['payload'];
          onEvent(
            type,
            payload is Map ? Map<String, dynamic>.from(payload) : const {},
          );
        }
      },
      onDone: _later,
      onError: (Object _) => _later(),
      cancelOnError: true,
    );
  }

  void _later() {
    _channel = null;
    final openedAt = _openedAt;
    _openedAt = null;
    if (openedAt != null && DateTime.now().difference(openedAt) >= _stable) {
      _attempt = 0;
    }
    if (_closed || _retry != null) return;
    final wait = Duration(seconds: 1 << (_attempt < 5 ? _attempt : 5));
    _attempt++;
    _retry = Timer(wait > _maxBackoff ? _maxBackoff : wait, () {
      _retry = null;
      unawaited(_connect());
    });
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) await ch.sink.close();
  }
}
