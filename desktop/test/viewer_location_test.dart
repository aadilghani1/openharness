import 'package:flutter_test/flutter_test.dart';
import 'package:harness/viewer/viewer_location.dart';

void main() {
  test(
    'viewer destinations round trip escaped identities without granting access',
    () {
      const path = '/?viewer=1&machine=server&agent=a%20%2F%3F%26%C3%A9';
      final location = ViewerLocation.parse(
        Uri.parse('https://harness.example$path'),
      )!;
      expect(location.machineId, 'server');
      expect(location.agentId, 'a /?&é');
      expect(ViewerLocation.returnPath(path), path);
      for (final invalid in [
        'https://other.example$path',
        '//other.example$path',
        '/auth/callback?code=secret',
        '/?viewer=1&machine=m',
        '/?viewer=1&machine=m&agent=',
        '/?viewer=1&machine=m&agent=a&agent=b',
        '/?viewer=1&machine=m&agent=%0A',
        '/view/else?machine=m&agent=a',
      ]) {
        expect(ViewerLocation.returnPath(invalid), isNull, reason: invalid);
      }
    },
  );

  test('viewer and OAuth tabs cannot restore terminal workspace', () {
    for (final path in [
      '/?viewer=1&machine=m&agent=a',
      '/?viewer=1',
      '/auth/callback',
      '/callback',
    ]) {
      expect(
        ViewerLocation.workspaceAllowed(
          Uri.parse('https://harness.example$path'),
        ),
        isFalse,
      );
    }
    expect(
      ViewerLocation.workspaceAllowed(Uri.parse('https://harness.example/')),
      isTrue,
    );
  });
}
