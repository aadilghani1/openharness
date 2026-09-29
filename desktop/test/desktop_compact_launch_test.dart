import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shortcuts/app_keymap.dart';
import 'package:harness/shortcuts/keymap_host.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/harness_placement.dart';
import 'package:harness/state/new_harness.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/widgets/new_harness_form.dart';

import 'box_render_preview_test.dart' show loadPreviewFonts;
import 'keymap_host_test.dart' show MemoryKeymap, key;

class _CompactApp extends AppNotifier {
  _CompactApp({String machineName = 'Studio Mac'})
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      ) {
    final machine = Machine(
      machineId: 'm',
      name: machineName,
      authMode: MachineAuthMode.remote,
    );
    machines = [machine];
    machineStates['m'] = MachineState(machine)
      ..localOnly = true
      ..connectionStatus = ConnectionStatus.connected
      ..agentLoadStatus = AgentLoadStatus.loaded
      ..engines.replace(const [
        EngineAvailability(
          engine: 'codex',
          installed: true,
          supportsCodexHome: true,
        ),
        EngineAvailability(engine: 'claude', installed: true),
      ]);
  }

  final launches = <Map<String, Object?>>[];
  bool missingMain = false;
  Completer<String?>? pendingLaunch;
  String? launchError = 'Fixture launch declined. Try again.';

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}
  @override
  Future<void> probeDsh(String machineId, {bool force = false}) async {}
  @override
  Future<Map<String, dynamic>> readGitProject(
    String machineId,
    String path, {
    bool refresh = false,
  }) async => {
    'isGit': true,
    'branch': missingMain ? 'feature' : 'main',
    'branches': [
      if (!missingMain) {'ref': 'refs/heads/main', 'name': 'main'},
      {'ref': 'refs/heads/feature', 'name': 'feature'},
    ],
  };
  @override
  Future<Map<String, dynamic>> listCodexProfiles(
    String machineId, {
    Set<String> observedPaths = const {},
  }) async => {
    'profiles': [
      {'path': '/profiles/work', 'label': 'Work'},
    ],
  };
  @override
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async => {'path': path ?? '/work', 'entries': []};

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String? folder,
    bool bypassPermission = false,
    String? permissionMode,
    String? codexHome,
    String? dsh,
    GridModel? model,
    String? prompt,
    String? name,
    String? agent,
    ProjectFolderRequest? projectFolder,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
    HarnessPlacement? placement,
  }) async {
    launches.add({
      'machine': machineId,
      'engine': engine,
      'folder': folder,
      'prompt': prompt,
      'permissions': permissionMode,
      'projectFolder': projectFolder,
    });
    return pendingLaunch?.future ?? Future.value(launchError);
  }
}

class _CompactFixture {
  _CompactFixture(this.app, this.box, this.map);
  final _CompactApp app;
  final NewHarnessController box;
  final MemoryKeymap map;
  final form = GlobalKey<NewHarnessFormState>();
  final image = GlobalKey();
  int closed = 0;
  int created = 0;

  void dispose() {
    box.dispose();
    map.dispose();
    app.dispose();
  }
}

final _surface = find.byKey(const ValueKey('new-harness-surface'));
final _task = find.byKey(const ValueKey('new-harness-task'));
final _toggleTask = find.byKey(const ValueKey('new-harness-task-toggle'));
final _options = find.byKey(const ValueKey('new-harness-field-advanced'));
final _start = find.byKey(const ValueKey('new-harness-field-start'));
final _machine = find.byKey(const ValueKey('new-harness-machine'));
final _close = find.byKey(const ValueKey('new-harness-close'));
final _chooser = find.byKey(const ValueKey('new-harness-chooser-surface'));

bool _focused(WidgetTester tester, Finder target) {
  final element = tester.element(target);
  var found = FocusManager.instance.primaryFocus?.context == element;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
    ancestor,
  ) {
    if (ancestor == element) found = true;
    return !found;
  });
  return found;
}

Future<void> _focus(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 32 && !_focused(tester, target); i++) {
    await key(tester, LogicalKeyboardKey.tab);
  }
  expect(
    _focused(tester, target),
    isTrue,
    reason: '$target must be reachable with Tab',
  );
}

Future<_CompactFixture> _mount(
  WidgetTester tester, {
  String engine = 'codex',
  NewHarnessDraft? draft,
  Size size = const Size(1100, 800),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  String machineName = 'Studio Mac',
  bool pending = false,
  bool missingMain = false,
  String? harnessId,
}) async {
  final app = _CompactApp(machineName: machineName);
  app.missingMain = missingMain;
  if (harnessId != null) {
    app.machineStates['m']!.dsh.replace([
      DshEntry(
        id: harnessId,
        name: 'Review Tool',
        engine: 'codex',
        description: 'Synthetic installed agent',
        installed: true,
      ),
    ]);
  }
  if (pending) app.pendingLaunch = Completer<String?>();
  final box = NewHarnessController(
    app,
    machineId: 'm',
    engine: engine,
    harnessId: harnessId,
    folder: '/work/repo',
    draft: draft,
  );
  final fixture = _CompactFixture(app, box, MemoryKeymap());
  addTearDown(fixture.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousBrightness = grid.AppTheme.brightness.value;
  grid.AppTheme.brightness.value = brightness;
  addTearDown(() => grid.AppTheme.brightness.value = previousBrightness);
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: KeymapProvider(
        keymap: fixture.map,
        child: KeymapHost(
          keymap: fixture.map,
          enabled: () => true,
          actions: const {},
          child: RepaintBoundary(
            key: fixture.image,
            child: Scaffold(
              backgroundColor: grid.AppPalette.windowBg,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('compact-workspace-backdrop'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          fixture.form.currentState?.dismissFromOutside(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: NewHarnessForm(
                      key: fixture.form,
                      controller: box,
                      desktop: true,
                      onClose: () => fixture.closed++,
                      onCreated: () => fixture.created++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

const _nativeCompactJourneys = {
  'empty launch is compact, machine-first, and ready for Return',
  'Start wraps forward to Machine and backward to Close',
  'Add task expands and Hide task restores its control (mouse=false)',
  'codex Options toggles without moving focus or replacing its settings',
  'quick settings survive Options, task expansion, and chooser acceptance',
  'an initially missing branch keeps Return and Escape inside the compact dialog',
  'an agent becoming unavailable while Start is focused preserves Escape',
};

void main({bool nativeSmoke = false}) {
  void journey(String description, Future<void> Function(WidgetTester) body) {
    if (nativeSmoke && !_nativeCompactJourneys.contains(description)) return;
    testWidgets(
      description,
      body,
      timeout: nativeSmoke ? const Timeout(Duration(seconds: 45)) : null,
    );
  }

  final renderDir = Platform.environment['COMPACT_LAUNCH_RENDER_DIR'];
  setUpAll(() async {
    if (renderDir != null) await loadPreviewFonts();
  });

  Future<void> capture(
    WidgetTester tester,
    _CompactFixture fixture,
    String name,
  ) async {
    if (renderDir == null) return;
    await tester.runAsync(() async {
      final boundary =
          fixture.image.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(renderDir)..createSync(recursive: true);
      await File('${folder.path}/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  journey('empty launch is compact, machine-first, and ready for Return', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    expect(tester.getSize(_surface).width, 560);
    expect(_task, findsNothing);
    expect(find.byKey(const ValueKey('new-harness-settings')), findsNothing);
    expect(
      find.byKey(const ValueKey('new-harness-field-approvals')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('new-harness-field-worktree')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-harness-field-model')), findsNothing);
    expect(
      find.byKey(const ValueKey('new-harness-field-branch')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(_machine).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('new-harness-field-project')))
            .dy,
      ),
    );
    expect(_focused(tester, _start), isTrue);
    await capture(tester, fixture, 'compact-dark');
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.app.launches, hasLength(1));
    expect(fixture.app.launches.single['prompt'], isNull);
    expect(fixture.app.launches.single['machine'], 'm');
    expect(fixture.app.launches.single['engine'], 'codex');
    expect(fixture.closed, 0);
  });

  journey('Start wraps forward to Machine and backward to Close', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await key(tester, LogicalKeyboardKey.tab);
    expect(
      _focused(tester, _machine),
      isTrue,
      reason:
          'After Start→Tab focus is ${FocusManager.instance.primaryFocus?.debugLabel}',
    );
    await key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(_focused(tester, _start), isTrue);
    await key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(_focused(tester, _close), isTrue);
    expect(fixture.app.launches, isEmpty);
  });

  journey(
    'an initially missing branch keeps Return and Escape inside the compact dialog',
    (tester) async {
      final fixture = await _mount(tester, missingMain: true);
      expect(fixture.box.requiredChoice?.field, NewHarnessField.branch);
      expect(tester.widget<FilledButton>(_start).onPressed, isNull);
      expect(_task, findsNothing);
      expect(_chooser, findsNothing);
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_chooser, findsOneWidget);
      expect(fixture.box.field, NewHarnessField.branch);
      expect(fixture.app.launches, isEmpty);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_chooser, findsNothing);
      expect(fixture.closed, 0);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.closed, 1);
      expect(fixture.app.launches, isEmpty);
    },
  );

  journey(
    'an agent becoming unavailable while Start is focused preserves Escape',
    (tester) async {
      final fixture = await _mount(tester, harnessId: 'fixture/review-tool');
      expect(_focused(tester, _start), isTrue);
      expect(fixture.box.requiredChoice, isNull);
      fixture.app.machineStates['m']!.dsh.replace(const []);
      fixture.app.notifyListeners();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(fixture.box.requiredChoice?.field, NewHarnessField.harness);
      expect(tester.widget<FilledButton>(_start).onPressed, isNull);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.closed, 1);
      expect(fixture.app.launches, isEmpty);
    },
  );

  for (final mouse in [true, false]) {
    journey(
      'Add task expands and Hide task restores its control (mouse=$mouse)',
      (tester) async {
        final fixture = await _mount(tester);
        final controller = fixture.box;
        final project = controller.project;
        final originalWorktree = controller.worktree;
        if (mouse) {
          await tester.tap(_toggleTask);
        } else {
          await _focus(tester, _toggleTask);
          await key(tester, LogicalKeyboardKey.enter);
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(_surface).width, 720);
        expect(_focused(tester, _task), isTrue);
        expect(
          tester.widget<NewHarnessForm>(find.byType(NewHarnessForm)).controller,
          same(controller),
        );
        expect(controller.project, project);
        expect(controller.worktree, originalWorktree);
        await capture(
          tester,
          fixture,
          'expanded-task-${mouse ? 'mouse' : 'keyboard'}',
        );
        await _focus(tester, _toggleTask);
        await key(tester, LogicalKeyboardKey.enter);
        expect(_task, findsNothing);
        expect(tester.getSize(_surface).width, 560);
        expect(_focused(tester, _toggleTask), isTrue);
        expect(fixture.app.launches, isEmpty);
      },
    );
  }

  journey('expanded task owns newlines and Cmd-Return submits the exact task', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await tester.tap(_toggleTask);
    await tester.pumpAndSettle();
    await tester.enterText(_task, 'Inspect launch');
    await key(tester, LogicalKeyboardKey.enter);
    expect(fixture.app.launches, isEmpty);
    // macOS text insertion follows the platform editing channel after the key.
    // sendKeyEvent alone does not synthesize that operating-system edit.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Inspect launch\n',
        selection: TextSelection.collapsed(offset: 15),
      ),
    );
    await tester.pump();
    expect(fixture.box.task, 'Inspect launch\n');
    await tester.enterText(_task, 'Inspect launch\nPreserve the settings');
    await key(tester, LogicalKeyboardKey.enter, cmd: true);
    await tester.pumpAndSettle();
    expect(fixture.app.launches, hasLength(1));
    expect(
      fixture.app.launches.single['prompt'],
      'Inspect launch\nPreserve the settings',
    );
  });

  journey('nonempty task cannot be hidden by its Edit task control', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await tester.tap(_toggleTask);
    await tester.pumpAndSettle();
    await tester.enterText(_task, 'Retain this draft');
    await tester.tap(_toggleTask);
    await tester.pumpAndSettle();
    expect(_task, findsOneWidget);
    expect(fixture.box.task, 'Retain this draft');
    expect(_focused(tester, _task), isTrue);
    await tester.enterText(_task, '');
    await tester.tap(_toggleTask);
    await tester.pumpAndSettle();
    expect(_task, findsNothing);
    expect(_focused(tester, _toggleTask), isTrue);
  });

  for (final engine in ['codex', 'claude', 'terminal']) {
    journey(
      '$engine Options toggles without moving focus or replacing its settings',
      (tester) async {
        final fixture = await _mount(tester, engine: engine);
        final engineBefore = fixture.box.engine;
        final projectBefore = fixture.box.project;
        await _focus(tester, _options);
        await key(tester, LogicalKeyboardKey.enter);
        expect(fixture.box.advancedOpen, isTrue);
        expect(_focused(tester, _options), isTrue);
        expect(tester.getSize(_surface).width, 720);
        expect(
          find.byKey(const ValueKey('new-harness-settings')),
          findsOneWidget,
        );
        if (engine == 'codex') {
          await capture(tester, fixture, 'expanded-settings-dark');
        }
        await key(tester, LogicalKeyboardKey.enter);
        expect(fixture.box.advancedOpen, isFalse);
        expect(_focused(tester, _options), isTrue);
        expect(tester.getSize(_surface).width, 560);
        expect(fixture.box.engine, engineBefore);
        expect(fixture.box.project, projectBefore);
        expect(fixture.app.launches, isEmpty);
      },
    );
  }

  for (final field in ['project', 'agent', 'approvals']) {
    journey('$field chooser dismisses one level and restores compact origin', (
      tester,
    ) async {
      final fixture = await _mount(tester);
      final target = find.byKey(ValueKey('new-harness-field-$field'));
      await _focus(tester, target);
      await key(tester, LogicalKeyboardKey.enter);
      expect(_chooser, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(_chooser, findsNothing);
      expect(find.byType(NewHarnessForm), findsOneWidget);
      expect(_focused(tester, target), isTrue);
      expect(fixture.closed, 0);
      expect(tester.getSize(_surface).width, 560);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(fixture.closed, 1);
    });
  }

  journey(
    'held Return and a busy Start produce one launch, with failure recovery',
    (tester) async {
      final fixture = await _mount(tester, pending: true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fixture.app.launches, hasLength(1));
      expect(tester.widget<FilledButton>(_start).onPressed, isNull);
      await tester.tap(_start, warnIfMissed: false);
      await tester.pump();
      expect(fixture.app.launches, hasLength(1));
      fixture.app.pendingLaunch!.complete('Offline. Try again.');
      await tester.pumpAndSettle();
      fixture.app.pendingLaunch = null;
      expect(find.text('Offline. Try again.'), findsWidgets);
      expect(tester.widget<FilledButton>(_start).onPressed, isNotNull);
      expect(
        _focused(tester, _start),
        isTrue,
        reason:
            'Failure should leave Return ready to retry without an extra Tab',
      );
      await _focus(tester, _start);
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fixture.app.launches, hasLength(2));
      expect(fixture.box.task, isEmpty);
      expect(_task, findsNothing);
    },
  );

  journey(
    'quick settings survive Options, task expansion, and chooser acceptance',
    (tester) async {
      final fixture = await _mount(tester);
      final worktree = find.byKey(const ValueKey('new-harness-field-worktree'));
      final before = fixture.box.worktree;
      await tester.tap(worktree);
      await tester.pumpAndSettle();
      expect(fixture.box.worktree, !before);
      await tester.tap(_options);
      await tester.pumpAndSettle();
      final branch = find.byKey(const ValueKey('new-harness-field-branch'));
      await tester.tap(branch);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(_focused(tester, branch), isTrue);
      expect(fixture.box.worktree, !before);
      await tester.tap(_options);
      await tester.pumpAndSettle();
      await tester.tap(_toggleTask);
      await tester.pumpAndSettle();
      await tester.enterText(_task, 'Preserve my worktree preference');
      final agent = find.byKey(const ValueKey('new-harness-field-agent'));
      await tester.tap(agent);
      await tester.pumpAndSettle();
      final claude = find.byKey(const ValueKey('new-harness-option-claude'));
      expect(claude, findsOneWidget);
      await tester.tap(claude);
      await tester.pumpAndSettle();
      expect(fixture.box.engine, 'claude');
      expect(fixture.box.task, 'Preserve my worktree preference');
      expect(fixture.box.worktree, !before);
      expect(_focused(tester, agent), isTrue);
      expect(fixture.app.launches, isEmpty);
    },
  );

  journey('IME composition in an expanded task blocks Return and Cmd-Return', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await tester.tap(_toggleTask);
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '選択',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.enter, cmd: true);
    expect(fixture.app.launches, isEmpty);
    expect(fixture.box.task, '選択');
    expect(_focused(tester, _task), isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '選択',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter, cmd: true);
    await tester.pumpAndSettle();
    expect(fixture.app.launches, hasLength(1));
    expect(fixture.app.launches.single['prompt'], '選択');
  });

  journey('Options-only draft restores its settings without opening task', (
    tester,
  ) async {
    final draft = NewHarnessDraft(
      machineId: 'm',
      engine: 'claude',
      project: const NewHarnessProject.folder('/work/repo'),
      task: '',
      permissionMode: 'default',
      advancedOpen: true,
      worktree: false,
    );
    final fixture = await _mount(tester, draft: draft);
    expect(_task, findsNothing);
    expect(find.byKey(const ValueKey('new-harness-settings')), findsOneWidget);
    expect(tester.getSize(_surface).width, 720);
    expect(_focused(tester, _start), isTrue);
    expect(fixture.box.engine, 'claude');
    expect(fixture.box.worktree, isFalse);
    await tester.tap(_options);
    await tester.pumpAndSettle();
    expect(tester.getSize(_surface).width, 560);
    expect(_focused(tester, _options), isTrue);
  });

  journey('restored task draft expands while an empty draft remains compact', (
    tester,
  ) async {
    final source = await _mount(tester);
    source.box.setTask('Draft from earlier');
    final draft = source.box.draft;
    await tester.pumpWidget(const SizedBox());
    final restored = await _mount(tester, draft: draft);
    expect(restored.box.task, 'Draft from earlier');
    expect(
      tester.widget<TextField>(_task).controller!.text,
      'Draft from earlier',
    );
    expect(_focused(tester, _task), isTrue);
    expect(tester.getSize(_surface).width, 720);
    restored.box.setTask('');
    final empty = restored.box.draft;
    await tester.pumpWidget(const SizedBox());
    final compact = await _mount(tester, draft: empty);
    expect(_task, findsNothing);
    expect(_focused(tester, _start), isTrue);
    expect(tester.getSize(_surface).width, 560);
    expect(compact.box.project, draft.project);
    expect(compact.box.worktree, draft.worktree);
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final scale in [1.0, 1.6]) {
      journey(
        'compact and expanded controls fit 600x520 ${brightness.name} scale=$scale',
        (tester) async {
          final fixture = await _mount(
            tester,
            size: const Size(600, 520),
            scale: scale,
            brightness: brightness,
            machineName: 'Studio Mac development workstation',
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(_surface).width, lessThanOrEqualTo(552));
          await capture(tester, fixture, 'compact-${brightness.name}-$scale');
          await _focus(tester, _toggleTask);
          await key(tester, LogicalKeyboardKey.enter);
          expect(_focused(tester, _task), isTrue);
          await tester.enterText(
            _task,
            'A task with enough text to wrap across the smaller window safely.',
          );
          await _focus(tester, _options);
          await key(tester, LogicalKeyboardKey.enter);
          expect(fixture.box.advancedOpen, isTrue);
          expect(tester.takeException(), isNull);
          await _focus(tester, _start);
          expect(_start.hitTestable(), findsOneWidget);
          await capture(
            tester,
            fixture,
            'compact-expanded-${brightness.name}-$scale',
          );
          expect(fixture.app.launches, isEmpty);
        },
      );
    }
  }
}
