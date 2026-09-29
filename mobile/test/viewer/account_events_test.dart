import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/viewer/account_events.dart';

import '../ws/memory_web_socket.dart';

void main() {
  test('hears the account pushes, catches up after a drop, and stops on close', () {
    fakeAsync((async) {
      final servers = <MemoryWebSocket>[];
      final protocols = <List<String>>[];
      final heard = <String>[];
      final events = AccountEvents(
        token: () async => 'hna_token',
        uri: Uri.parse('wss://api.invalid/api/web-ws'),
        socket: (uri, p) {
          protocols.add([...p]);
          final (client, server) = MemoryWebSocket.pair();
          servers.add(server);
          client.accept();
          return client;
        },
        onEvent: (type, payload) => heard.add('$type ${payload['revision']}'),
      )..start();
      async.flushMicrotasks();
      expect(protocols, [
        ['hna_token'],
      ]);

      servers.last.sink.add(
        jsonEncode({
          'type': 'group_changed',
          'payload': {'revision': 3},
        }),
      );
      servers.last.sink.add(jsonEncode({'type': 'desk_changed'}));
      async.flushMicrotasks();
      expect(heard, ['group_changed 3']);

      // A drop: redialled after a second, and whatever was pushed meanwhile is re-read.
      servers.last.close();
      async.elapse(const Duration(seconds: 1));
      expect(servers, hasLength(2));
      expect(heard, [
        'group_changed 3',
        'group_changed null',
        'machines_changed null',
      ]);

      events.close();
      async.elapse(const Duration(minutes: 1));
      expect(servers, hasLength(2));
    });
  });
}
