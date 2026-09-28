import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/agent_swipe.dart';
import 'package:harness_mobile/phone/new_agent_draft.dart';
import 'package:harness_mobile/phone/new_agent_page.dart';
import 'package:harness_mobile/phone/find_row.dart';
import 'package:harness_mobile/phone/tty_controls.dart' show TtyFieldMic;
import 'package:harness_mobile/state/app_state.dart';

import 'edge_fixture.dart';

/// New as somebody fills it in: every chooser, every option, the draft kept on the way out, a
/// double tap on Start, and a machine that goes away mid-form.
void main() {
  tearDown(() => newAgentDraft = null);

  /// A second machine, and what each answers about its engines, profiles and repositories.
  const answers = {
    'engines_probe': {
      'engines': [
        {'engine': 'claude', 'installed': true},
        {'engine': 'codex', 'installed': true, 'supportsCodexHome': true},
        {'engine': 'opencode', 'installed': false, 'installable': false},
      ],
    },
    'codex_profiles_list': {
      'profiles': [
        {'path': '/home/ada/.codex-work', 'label': 'work'},
        {'path': '/home/ada/.codex-home', 'label': 'home'},
      ],
    },
    'git_project_info': {
      'isGit': true,
      'branch': 'main',
      'root': '/code/web',
      'defaultRef': 'refs/heads/main',
      'branches': [
        {'ref': 'refs/heads/main', 'name': 'main'},
        {'ref': 'refs/heads/fix/login', 'name': 'fix/login'},
        {
          'ref': 'refs/remotes/origin/main',
          'name': 'origin/main',
          'remote': true,
        },
      ],
    },
  };

  Future<({AppNotifier app, EdgeConn conn})> openNew(
    WidgetTester tester, {
    bool twoMachines = false,
    bool makesProjects = true,
    List<Agent>? agents,
  }) async {
    setPhone(tester, largePhone);
    final conn = EdgeConn(answers, startsAgents);
    if (!makesProjects) {
      conn.capabilities = {...conn.capabilities, 'features': {}};
    }
    final app = edgeApp(conn: conn, agents: agents ?? [edgeAgent('a')]);
    app.stateOf('m')!
      ..projectFolderAvailable = makesProjects
      ..terminalCapabilityLoaded = true;
    if (twoMachines) {
      const other = Machine(
        machineId: 'mini',
        authMode: MachineAuthMode.remote,
        name: 'mini',
      );
      app.machines = [...app.machines, other];
      app.machineStates['mini'] = MachineState(other)
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected
        ..agentLoadStatus = AgentLoadStatus.loaded
        ..agents = [edgeAgent('x', project: 'api')];
    }
    await tester.pumpWidget(
      phoneApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NewAgentPage(
                  notifier: app,
                  machineId: 'm',
                  voice: edgeVoice().voice,
                ),
              ),
            ),
            child: const Text('focus'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('focus'));
    await frames(tester);
    return (app: app, conn: conn);
  }

  Future<void> close(WidgetTester tester, AppNotifier app) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    app.dispose();
    await tester.pump(const Duration(seconds: 30));
  }

  Future<void> choose(WidgetTester tester, String row, String item) async {
    await tapInView(tester, find.text(row));
    await frames(tester);
    await tapInView(tester, find.text(item, findRichText: true).last);
    await frames(tester);
  }

  testWidgets('a double tap on Start starts one harness, not two', (
    tester,
  ) async {
    final (:app, :conn) = await openNew(tester);
    final start = tester.getCenter(find.text('Start'));
    await tester.tapAt(start);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(start);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(start);
    await frames(tester, count: 20);
    expect(conn.payloads['agent_create'], hasLength(1));
    expect(find.byType(AgentSwipeHost), findsOneWidget);
    await close(tester, app);
  });

  testWidgets(
    'a suggestion fills the task; a long one counts toward its limit',
    (tester) async {
      // Nothing running: the first-task chips are a first harness's alone.
      final (:app, :conn) = await openNew(tester, agents: []);
      await tester.tap(find.text('Run the tests'));
      await tester.pump();
      expect(find.text('Run the tests'), findsOneWidget);
      expect(find.text('Explain this project to me'), findsNothing);

      await tester.enterText(find.byType(TextField), 'x' * 1900);
      await tester.pump();
      expect(find.textContaining('1900/'), findsOneWidget);
      // Starting with a long task is the next test's; with no harness yet there is no project
      // chosen for this one to start in.
      expect(conn.payloads['agent_create'], isNull);
      await close(tester, app);
    },
  );

  testWidgets('the agent chooser: Codex, its profiles and its approvals', (
    tester,
  ) async {
    final (:app, :conn) = await openNew(tester);
    await choose(tester, 'agent', 'Codex');
    expect(find.text('Codex', findRichText: true), findsWidgets);

    expect(find.text('profile'), findsNothing);
    expect(find.text('approvals'), findsNothing);
    expect(find.text('branch'), findsNothing);
    await tapInView(tester, find.text('options'));
    await frames(tester);
    await choose(tester, 'profile', 'work');
    await tapInView(tester, find.text('approvals'));
    await frames(tester);
    final modes = find.byType(ListView).last;
    expect(modes, findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(ModalBarrier).last));
    await frames(tester);

    // Collapsing Options hides the rows without discarding the chosen profile.
    await tapInView(tester, find.text('options'));
    await frames(tester);
    expect(find.text('profile'), findsNothing);

    await tapInView(tester, find.text('Start'));
    await frames(tester, count: 20);
    final created = conn.payloads['agent_create']!.single;
    expect(created['engine'], 'codex');
    expect(created['codexHome'], '/home/ada/.codex-work');
    await close(tester, app);
  });

  testWidgets('an engine the machine cannot install is offered, and says so', (
    tester,
  ) async {
    final (:app, conn: _) = await openNew(tester);
    await tapInView(tester, find.text('agent'));
    await frames(tester);
    expect(find.text('more'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('not installed'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('not installed'), findsWidgets);
    await close(tester, app);
  });

  testWidgets('the branch: this folder, a new worktree, another branch, a '
      'new name', (tester) async {
    final (:app, :conn) = await openNew(tester);
    expect(find.text('branch'), findsNothing);
    await tapInView(tester, find.text('options'));
    await frames(tester);
    expect(find.text('branch'), findsOneWidget);

    await choose(tester, 'branch', 'New Worktree');
    expect(find.textContaining('in its own folder'), findsWidgets);
    await choose(tester, 'branch', 'main');

    await choose(tester, 'branch', '+ Other Branch');
    // The branch picker: pick an existing one.
    await tapInView(tester, find.text('fix/login', findRichText: true).last);
    await frames(tester);

    // And a new name, cleaned the way Git takes it.
    await choose(tester, 'branch', '+ Other Branch');
    final typeOne = find.textContaining('New branch', findRichText: true);
    if (typeOne.evaluate().isNotEmpty) {
      await tester.tap(typeOne.last);
      await frames(tester);
      await tester.enterText(find.byType(TextField).last, 'fix the login');
      await tester.pump();
      expect(find.text('Git will call it fix-the-login'), findsOneWidget);
      await tester.tap(find.text('Use'));
      await frames(tester);
    }

    await tapInView(tester, find.text('Start'));
    await frames(tester, count: 20);
    expect(conn.payloads['agent_create'], hasLength(1));
    await close(tester, app);
  });

  testWidgets('the project: a folder on another computer moves the harness '
      'there', (tester) async {
    final (:app, :conn) = await openNew(tester, twoMachines: true);
    await choose(tester, 'project', 'api');
    expect(find.text('mini:api', findRichText: true), findsWidgets);
    await tapInView(tester, find.text('Start'));
    await frames(tester, count: 20);
    await close(tester, app);
  });

  testWidgets('agents are offered in most recently used order', (tester) async {
    final (:app, conn: _) = await openNew(tester);
    await app.agentPreference.select('claude');
    await app.agentPreference.select('opencode');
    await app.agentPreference.select('codex');
    await tapInView(tester, find.text('agent'));
    await frames(tester);
    final titles = tester
        .widgetList<FindRow>(find.byType(FindRow))
        .map((row) => row.title)
        .toList();
    expect(titles.take(3), ['Codex', 'OpenCode', 'Claude Code']);
    expect(find.text('more'), findsNothing);
    await close(tester, app);
  });

  testWidgets('the project picker is ready to type without tapping its field', (
    tester,
  ) async {
    final (:app, conn: _) = await openNew(tester, twoMachines: true);
    await tapInView(tester, find.text('project'));
    await frames(tester);
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'api'),
    );
    await frames(tester);
      expect(
        find.descendant(
          of: find.byType(FindRow),
          matching: find.text('api', findRichText: true),
        ),
        findsOneWidget,
      );
    expect(find.text('web', findRichText: true), findsNothing);
    await close(tester, app);
  });

  testWidgets('the project: a new folder, and a repository by URL', (
    tester,
  ) async {
    final (:app, :conn) = await openNew(tester);
    await choose(tester, 'project', '+ New Folder');
    expect(find.text('studio:New folder', findRichText: true), findsWidgets);

    await choose(tester, 'project', '+ Clone Repository');
    await tester.enterText(find.byType(TextField).last, 'not a repository');
    await tester.tap(find.text('Select'));
    await tester.pump();
    expect(find.text('That is not a GitHub repository.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'https://github.com/ada/engine',
    );
    await tester.tap(find.text('Select'));
    await frames(tester);
    expect(find.text('studio:engine', findRichText: true), findsWidgets);

    await tapInView(tester, find.text('Start'));
    await frames(tester, count: 20);
    expect(conn.payloads['agent_create'], hasLength(1));
    await close(tester, app);
  });

  testWidgets('a computer too old to make a project is not offered it', (
    tester,
  ) async {
    final (:app, conn: _) = await openNew(tester, makesProjects: false);
    await tapInView(tester, find.text('project'));
    await frames(tester);
    // Left out rather than drawn dead (see `new_agent_chooser.dart`).
    expect(find.text('+ Open Folder', findRichText: true), findsOneWidget);
    expect(find.text('+ Clone Repository', findRichText: true), findsNothing);
    expect(find.text('+ New Folder', findRichText: true), findsNothing);
    await close(tester, app);
  });

  testWidgets('no project yet: Start asks for one first', (tester) async {
    final (:app, :conn) = await openNew(tester, agents: []);
    expect(find.text('Choose a project', findRichText: true), findsWidgets);
    await tapInView(
      tester,
      find.text('Choose a project', findRichText: true).last,
    );
    await frames(tester);
    expect(find.text('+ Open Folder', findRichText: true), findsOneWidget);
    expect(conn.payloads['agent_create'], isNull);
    await close(tester, app);
  });

  testWidgets('the form is kept on the way out, and back on the way in', (
    tester,
  ) async {
    final (:app, conn: _) = await openNew(tester);
    await tester.enterText(find.byType(TextField), 'write the release notes');
    await tester.binding.handlePopRoute();
    await frames(tester, count: 6);
    expect(newAgentDraft?.task, 'write the release notes');

    await tester.tap(find.text('focus'));
    await frames(tester);
    expect(find.text('write the release notes'), findsOneWidget);

    // Nothing typed and nothing chosen is not a draft.
    await tester.enterText(find.byType(TextField), '');
    await tester.binding.handlePopRoute();
    await frames(tester, count: 6);
    await close(tester, app);
  });

  testWidgets('its computer goes offline mid-form: the form stays, and says so '
      'on Start', (tester) async {
    final (:app, conn: _) = await openNew(tester);
    await app.handleMachineEventForTest('m', {
      'type': 'node_status',
      'payload': {'online': false},
    });
    await frames(tester);
    expect(find.byType(NewAgentPage), findsOneWidget);
    await tapInView(tester, find.text('Start'));
    await frames(tester, count: 20);
    expect(tester.takeException(), isNull);
    await close(tester, app);
  });

  testWidgets('said into the task: added to what was typed', (tester) async {
    setPhone(tester, largePhone);
    final app = edgeApp();
    final voice = edgeVoice();
    voice.stt.replies.add(' then deploy it ');
    await tester.pumpWidget(
      phoneApp(NewAgentPage(notifier: app, machineId: 'm', voice: voice.voice)),
    );
    await frames(tester);
    await tester.enterText(find.byType(TextField), 'fix the tests');
    await tester.tap(find.byType(TtyFieldMic));
    await frames(tester);
    await tester.tap(find.byType(TtyFieldMic));
    await frames(tester);
    expect(find.text('fix the tests then deploy it'), findsOneWidget);
    await close(tester, app);
  });

  testWidgets('Open Folder: the computer\'s folders, and back out', (
    tester,
  ) async {
    final (:app, conn: _) = await openNew(tester);
    await choose(tester, 'project', '+ Open Folder');
    expect(find.text('Cancel'), findsWidgets);
    await tester.tap(find.text('Cancel').last);
    await frames(tester);
    expect(find.text('studio:web', findRichText: true), findsWidgets);
    await close(tester, app);
  });

  testWidgets('a draft with no agent chosen: Start asks for one', (
    tester,
  ) async {
    newAgentDraft = const NewAgentDraft(
      machineId: 'm',
      engine: null,
      permissionMode: 'auto',
      folder: '/code/web/',
      task: 'pick up where I left off',
    );
    final (:app, :conn) = await openNew(tester);
    expect(find.text('Choose an agent', findRichText: true), findsWidgets);
    await tapInView(tester, find.text('Choose an agent').last);
    await frames(tester);
    expect(find.text('Agent'), findsOneWidget);
    expect(conn.payloads['agent_create'], isNull);
    await close(tester, app);
  });

  testWidgets('a repository the computer could not read says so', (
    tester,
  ) async {
    setPhone(tester, largePhone);
    final app = edgeApp(
      conn: EdgeConn(const {
        'git_project_info': {'error': 'E2EE_REQUIRED'},
      }),
    );
    await tester.pumpWidget(
      phoneApp(NewAgentPage(notifier: app, machineId: 'm')),
    );
    await frames(tester);
    await tapInView(tester, find.text('options'));
    await frames(tester);
    expect(
      find.text('No answer from the computer', findRichText: true),
      findsOneWidget,
    );
    await close(tester, app);
  });

  testWidgets('the task\'s mic, with the page\'s own voice when none is given', (
    tester,
  ) async {
    // The microphone plugin's channel: permission refused, so nothing records.
    const record = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(record, (call) async {
          if (call.method == 'hasPermission') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(record, null),
    );
    setPhone(tester, largePhone);
    final app = edgeApp();
    await tester.pumpWidget(
      phoneApp(NewAgentPage(notifier: app, machineId: 'm')),
    );
    await frames(tester);
    await tester.tap(find.byType(TtyFieldMic));
    await frames(tester);
    expect(tester.takeException(), isNull);
    await close(tester, app);
  });
}
