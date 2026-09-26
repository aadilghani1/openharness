import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/phone/terminal_page.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:xterm/xterm.dart';

import 'voice_fakes.dart';

/// Reading back through the history while the agent keeps writing: output
/// never moves the screen being read, and "Latest" is one tap back to the end.
void main() {
  late AppNotifier notifier;
  late TerminalSession session;
  late VoiceInputController voice;
  late ValueNotifier<String> language;
  late List<Map<String, dynamic>> resizes;

  setUp(() {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    resizes = [];
    session = TerminalSession(
      machineId: 'm',
      agentId: 'a',
      agentName: 'Agent',
      engineId: 'claude',
      send: (type, payload) async {
        if (type == 'terminal_resize') resizes.add(payload);
        return true;
      },
      sendBinary: (_) async => true,
    );
    session.status = TerminalSessionStatus.controlling;
    session.streamId = 's';
    for (var line = 0; line < 400; line++) {
      session.terminal.write('output line $line\r\n');
    }
    notifier.adoptSessionForTest(session);
    language = ValueNotifier('en');
    voice = VoiceInputController(
      transcriber: FakeTranscriber().call,
      recorder: FakeVoiceRecorder(),
      language: language,
    );
  });

  tearDown(() {
    voice.dispose();
    language.dispose();
    // Disposes the session too: it was adopted as a pane.
    notifier.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          notifier: notifier,
          machineId: 'm',
          agentId: 'a',
          voice: voice,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A chunk of output, the way the session writes it.
  void output(String text) {
    session.outputTicks.value++;
    session.terminal.write(text);
  }

  testWidgets('output while at the end shows no chip', (tester) async {
    await pumpPage(tester);
    output('more output\r\n');
    await tester.pump();
    expect(find.text('Latest'), findsNothing);
  });

  testWidgets('scrolled up, new output brings Latest; a tap goes back', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.drag(find.byType(TerminalView), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Latest'), findsNothing);

    output('newer output\r\n');
    await tester.pump();
    expect(find.text('Latest'), findsOneWidget);

    await tester.tap(find.text('Latest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Latest'), findsNothing);

    // Following again: more output keeps it gone.
    output('newest output\r\n');
    await tester.pump();
    expect(find.text('Latest'), findsNothing);
  });
}
