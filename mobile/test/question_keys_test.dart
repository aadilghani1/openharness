import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/question_keys.dart';
import 'package:harness_mobile/terminal/question_pane.dart';

/// Claude's permission dialog, as the pane shows it.
final _permission = parseQuestionLines([
  ' Bash command',
  '   rm -rf build/',
  ' Do you want to proceed?',
  ' ❯ 1. Yes',
  "   2. Yes, and don't ask again for rm commands in /code/api",
  '   3. No, and tell Claude what to do differently (esc)',
  '',
  ' Esc to cancel · Enter to confirm',
], QuestionEngine.claude)!;

void main() {
  test('the keys are the rows, shortened to what a person would say', () {
    expect(questionKeys(_permission), [
      (label: 'yes', number: '1'),
      (label: 'always', number: '2'),
      (label: 'no', number: '3'),
    ]);
  });

  test('a spoken answer presses its key', () {
    String? press(String said) => matchSpokenAnswer(said, _permission)?.number;
    expect(press('Yes.'), '1');
    expect(press('yeah'), '1');
    expect(press('one'), '1');
    expect(press('2'), '2');
    expect(press('always'), '2');
    expect(press('option three'), '3');
    expect(press('nope'), '3');
  });

  test('"no, …" presses no and keeps the rest to send after', () {
    expect(matchSpokenAnswer('No, use dist instead', _permission), (
      number: '3',
      rest: 'use dist instead',
    ));
  });

  test('anything else matches nothing — it must never reach the dialog', () {
    expect(matchSpokenAnswer('fix the login test', _permission), isNull);
    expect(matchSpokenAnswer('seven', _permission), isNull);
    expect(matchSpokenAnswer('', _permission), isNull);
  });
}
