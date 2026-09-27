import 'support/open_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shortcuts/app_keymap.dart';
import 'package:harness/state/session_content_search.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/widgets/swarm_switcher.dart';

import 'keymap_host_test.dart' show MemoryKeymap, key;
import 'session_content_search_test.dart' show SearchConnection;
import 'swarm_state_test.dart' show createApp;

void main() {
  testWidgets(
    'a harness found by what was said in it shows where, in place of its context',
    (tester) async {
      final connection = SearchConnection({
        'retention cohorts': [
          {
            'agentId': 'a7',
            'sessionId': 's7',
            'field': 'ask',
            'snippet':
                'compare ${kSnippetMarkOpen}retention$kSnippetMarkClose by '
                '$kSnippetMarkOpen${'cohort'}$kSnippetMarkClose',
            'together': true,
            'score': .9,
          },
        ],
      });
      final app = createApp(
        connected: true,
        connectionForTest: (_) => connection,
      );
      final map = MemoryKeymap();
      final projects = SwarmProjectStore();
      addTearDown(map.dispose);
      addTearDown(projects.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          builder: (_, child) => grid.BrightnessScope(
            child: KeymapProvider(keymap: map, child: child!),
          ),
          home: SwarmScreen(
            notifier: app,
            nativeTabs: false,
            projectStore: projects,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await openHarnessPicker(tester);
      await tester.enterText(
        find.byKey(const ValueKey('swarm-search-input')),
        'retention cohorts',
      );
      // Past the pause-in-typing debounce, then the reply.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));
      final search = tester
          .widget<SwarmSearchResults>(find.byType(SwarmSearchResults))
          .search;
      expect(search.selected!.agentId, 'a7');
      final snippet = find.byKey(
        ValueKey('session-snippet:${agentDestinationId('m', 'a7')}'),
      );
      expect(snippet, findsOneWidget);
      expect(
        tester.widget<Text>(snippet).textSpan!.toPlainText(),
        '> compare retention by cohort',
      );
      final found = find.byKey(
        ValueKey('preview-found:${agentDestinationId('m', 'a7')}'),
      );
      expect(found, findsOneWidget);
      final foundText = find.descendant(of: found, matching: find.byType(Text));
      expect(
        tester.widget<Text>(foundText).textSpan!.toPlainText(),
        '> compare retention by cohort',
      );
      expect(tester.widget<Text>(foundText).maxLines, isNull);
      expect(find.text('Found in what you asked'), findsOneWidget);
      app.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a session previews its latest turns from the bottom up, and pages up for older ones',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final tails = <int?>[];
      Map<String, dynamic> row(int turn) => {
        'turn': turn,
        'at': DateTime.now()
            .subtract(Duration(hours: 20 - turn))
            .millisecondsSinceEpoch,
        'ask': 'step $turn of the retention report',
        'answer': [
          'answer $turn',
          for (var line = 0; line < 12; line++) 'line $line of turn $turn',
        ].join('\n'),
        'tools': 'Bash python3 cohorts.py --turn $turn',
      };
      final connection = TailConnection(
        {
          'retention cohorts': [
            {
              'agentId': 'a7',
              'sessionId': 's7',
              'field': 'ask',
              'turn': 2,
              'snippet':
                  'compare ${kSnippetMarkOpen}retention$kSnippetMarkClose',
              'together': true,
              'score': .9,
            },
          ],
        },
        tail: (payload) {
          final before = payload['beforeTurn'] as int?;
          tails.add(before);
          return before == null
              ? {
                  'rows': [for (var turn = 10; turn < 15; turn++) row(turn)],
                  'hasMore': true,
                  'total': 15,
                  'lastAsk': row(14),
                }
              : {
                  'rows': [for (var turn = 5; turn < before; turn++) row(turn)],
                  'hasMore': false,
                  'total': 15,
                };
        },
      );
      final app = createApp(
        connected: true,
        connectionForTest: (_) => connection,
      );
      final machine = app.machineStates['m']!;
      machine.agents = [
        for (final agent in machine.agents)
          agent.id == 'a7'
              ? Agent(
                  id: 'a7',
                  sessionId: 's7',
                  name: 'Agent 7',
                  engine: 'codex',
                  terminalAvailable: true,
                )
              : agent,
      ];
      // At work: its preview is still fetched once, never refreshed.
      machine.processingAgentIds.add('a7');
      final map = MemoryKeymap();
      final projects = SwarmProjectStore();
      addTearDown(map.dispose);
      addTearDown(projects.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          builder: (_, child) => grid.BrightnessScope(
            child: KeymapProvider(keymap: map, child: child!),
          ),
          home: SwarmScreen(
            notifier: app,
            nativeTabs: false,
            projectStore: projects,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await openHarnessPicker(tester);
      await tester.enterText(
        find.byKey(const ValueKey('swarm-search-input')),
        'retention cohorts',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));
      // The selected row's latest turns, a moment after it stays selected.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tails, [null]);
      await tester.pump(const Duration(seconds: 10));
      expect(tails, [null], reason: 'nothing refreshes while Cmd-P is open');
      expect(find.text('Working'), findsOneWidget);

      final list = find.byKey(const ValueKey('session-tail:m:s7'));
      expect(list, findsOneWidget);
      // Newest at the bottom, the turn before it above.
      final newest = find.textContaining(
        'line 11 of turn 14',
        findRichText: true,
      );
      final before = find.textContaining('answer 13', findRichText: true);
      expect(newest, findsOneWidget);
      expect(before, findsOneWidget);
      expect(
        tester.getTopLeft(before).dy,
        lessThan(tester.getTopLeft(newest).dy),
      );
      final listBox = tester.getRect(list);
      expect(
        tester.getBottomLeft(newest).dy,
        lessThanOrEqualTo(listBox.bottom),
      );
      // The match was older than what is shown: where it was, above.
      expect(find.text('Matched earlier · 20h ago'), findsNothing);
      expect(find.textContaining('Matched earlier'), findsOneWidget);
      // The searched words stand out in the turns.
      final ask = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('step 14 of the retention'),
        ),
      );
      final bold = <String>[];
      ask.text.visitChildren((span) {
        if (span is TextSpan &&
            span.style?.fontWeight == FontWeight.w700 &&
            span.text != null) {
          bold.add(span.text!);
        }
        return true;
      });
      expect(bold, ['retention']);

      // One scrollbar, on the turns alone: macOS gives every list its own,
      // and none may wrap the whole preview besides.
      expect(
        find.descendant(
          of: find.ancestor(of: list, matching: find.byType(Semantics)).first,
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: list, matching: find.byType(Scrollbar)),
        findsNothing,
      );

      // The latest ask is in view, so nothing is pinned above the turns.
      expect(find.byKey(const ValueKey('preview-last-ask')), findsNothing);

      // Shift-Up scrolls toward older turns, Shift-Down back.
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.position.pixels, 0);
      await key(tester, LogicalKeyboardKey.arrowUp, shift: true);
      await tester.pump();
      expect(controller.position.pixels, greaterThan(0));
      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      await tester.pump();
      expect(controller.position.pixels, 0);

      // Near the top, the page above is asked for and joins beneath it.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tails, [null, 10]);
      // Scrolled away from it, the latest ask is pinned above the turns.
      expect(find.byKey(const ValueKey('preview-last-ask')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preview-last-ask')),
          matching: find.textContaining('step 14 of the retention report'),
        ),
        findsOneWidget,
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(
        find.textContaining('answer 5', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Start of session'), findsOneWidget);

      app.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}

/// A machine that searches and previews: `session_tail` answered by [tail].
class TailConnection extends SearchConnection {
  TailConnection(super.answers, {required this.tail});

  final Map<String, dynamic> Function(Map<String, dynamic> payload) tail;

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (type == 'session_tail') return tail(payload);
    return super.request(type, payload: payload, timeout: timeout);
  }
}
