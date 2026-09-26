import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/find_handle.dart';

/// The foot of Focus: a tap or a swipe up on it opens Find, and nothing else does.
void main() {
  Future<List<int>> pumpHandle(WidgetTester tester) async {
    final opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FindHandle(onOpen: () => opened.add(opened.length)),
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('a tap opens Find', (tester) async {
    final opened = await pumpHandle(tester);
    await tester.tap(find.byType(FindHandle));
    expect(opened, hasLength(1));
    expect(find.text('Find'), findsOneWidget);
  });

  testWidgets('a swipe up opens Find once, however far it goes', (
    tester,
  ) async {
    final opened = await pumpHandle(tester);
    await tester.drag(find.byType(FindHandle), const Offset(0, -120));
    await tester.pump();
    expect(opened, hasLength(1));
  });

  testWidgets('a swipe down opens nothing', (tester) async {
    final opened = await pumpHandle(tester);
    await tester.drag(find.byType(FindHandle), const Offset(0, 80));
    await tester.pump();
    expect(opened, isEmpty);
  });
}
