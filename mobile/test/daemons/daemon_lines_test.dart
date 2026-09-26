// What the daemon says on the phone is true: slots are filled from what the
// phone knows, a sentence with a slot it cannot fill is dropped, and a roster
// whose lines are still written-out examples is never repeated as fact.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/daemons/daemon_lines.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/roster.g.dart';

DaemonRoster _templated(Map<String, String> lines) {
  final raw = jsonDecode(daemonRosterJson) as Map<String, dynamic>;
  (raw['rules'] as Map)['lineSlots'] = ['who', 'q', 'recap', 'n', 'summary'];
  final tim = (raw['daemons'] as List).first as Map;
  tim['lines'] = {...tim['lines'] as Map, ...lines};
  return DaemonRoster.parse(jsonEncode(raw));
}

void main() {
  const facts = DaemonFacts(
    waiting: [(who: 'codex', q: 'run the migration?')],
    working: ['claude', 'codex'],
    failing: ['docs'],
    harnesses: 4,
  );

  test('a template fills its slots and drops what it cannot fill', () {
    expect(
      fillLine('{who} asks: {q} i would say yes.', {
        'who': 'codex',
        'q': 'run it?',
      }),
      'codex asks: run it? i would say yes.',
    );
    expect(
      fillLine('{who} is done. {recap}', {'who': 'claude', 'recap': null}),
      'claude is done.',
    );
    // Nothing but an answer hint left is not a line.
    expect(fillLine('{recap} [y/n]', {'recap': null}), isNull);
    expect(fillLine('{summary}', const {}), isNull);
  });

  test('a line never shows a literal slot', () {
    final roster = _templated({
      'need': '{who} wants you: {q} [y/n]',
      'work': '{n} busy. {recap}',
      'done': '{recap}',
      'idle': '{n} idle. {summary}',
    });
    final tim = roster.byId('tim')!;
    expect(
      daemonLine(roster, tim, DaemonMood.need, facts),
      'codex wants you: run the migration? [y/n]',
    );
    expect(daemonLine(roster, tim, DaemonMood.work, facts), '2 busy.');
    expect(daemonLine(roster, tim, DaemonMood.idle, facts), '4 idle.');
    // Nothing the phone can fill: the neutral line instead.
    expect(
      daemonLine(roster, tim, DaemonMood.done, facts),
      '4 harnesses idle. nothing needs you.',
    );
    for (final mood in DaemonMood.values) {
      final line = daemonLine(roster, tim, mood, const DaemonFacts());
      expect(line, isNot(contains('{')), reason: mood.name);
      expect(line, isNotEmpty);
    }
  });

  test('written-out example lines are not repeated as fact', () {
    final tim = daemonRoster.byId('tim')!;
    if (daemonRoster.rules.lineSlots != null) return; // templates have landed
    expect(
      daemonLine(daemonRoster, tim, DaemonMood.need, facts),
      'codex needs you.',
    );
    expect(
      daemonLine(daemonRoster, tim, DaemonMood.work, facts),
      '2 harnesses working.',
    );
    expect(
      daemonLine(daemonRoster, tim, DaemonMood.fail, facts),
      'docs failed to start.',
    );
    expect(
      daemonLine(daemonRoster, tim, DaemonMood.idle, const DaemonFacts()),
      'nothing needs you.',
    );
    // A boop is only the daemon talking about itself.
    expect(
      daemonLine(daemonRoster, tim, DaemonMood.boop, facts),
      tim.line(DaemonMood.boop),
    );
  });

  test('neutral lines count what they say', () {
    expect(
      neutralLine(
        DaemonMood.need,
        const DaemonFacts(waiting: [(who: 'a', q: null), (who: 'b', q: null)]),
      ),
      '2 harnesses need you.',
    );
    expect(
      neutralLine(DaemonMood.work, const DaemonFacts(working: ['claude'])),
      'claude is working.',
    );
    expect(
      neutralLine(DaemonMood.idle, const DaemonFacts(harnesses: 1)),
      '1 harness idle. nothing needs you.',
    );
  });
}
