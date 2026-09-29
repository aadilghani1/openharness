import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
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
import 'package:harness/widgets/desktop_chrome.dart';
import 'package:harness/widgets/engine_identity.dart';
import 'package:harness/widgets/new_harness_form.dart';

import 'box_render_preview_test.dart' show loadPreviewFonts;
import 'keymap_host_test.dart' show MemoryKeymap, key;

/// A launch boundary that records the user's reviewed choices without starting
/// an agent, preparing a worktree, or contacting a real machine.
class _ReviewApp extends AppNotifier {
  _ReviewApp({
    required String machineName,
    this.git = true,
    this.branchNames = const ['main', 'feature/review'],
  }) : super(
         config: AppConfig.dev,
         authSession: AuthSession(),
         configStore: null,
       ) {
    final machine = Machine(
      machineId: 'review',
      name: machineName,
      authMode: MachineAuthMode.remote,
    );
    machines = [machine];
    machineStates[machine.machineId] = MachineState(machine)
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

  final bool git;
  final List<String> branchNames;
  final launches = <Map<String, Object?>>[];

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
    'isGit': git,
    if (git) ...{
      'branch': 'main',
      'branches': [
        for (final name in branchNames)
          {'ref': 'refs/heads/$name', 'name': name},
      ],
    },
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
      'profile': codexHome,
      'projectFolder': projectFolder,
    });
    return 'Synthetic review stops at the launch boundary.';
  }
}

class _ReviewFixture {
  _ReviewFixture(this.app, this.box, this.map);

  final _ReviewApp app;
  final NewHarnessController box;
  final MemoryKeymap map;
  final form = GlobalKey<NewHarnessFormState>();
  final image = GlobalKey();
  int closes = 0;

  void dispose() {
    box.dispose();
    map.dispose();
    app.dispose();
  }
}

Finder _field(String name) => find.byKey(ValueKey('new-harness-field-$name'));
final _surface = find.byKey(const ValueKey('new-harness-surface'));
final _composer = find.byKey(const ValueKey('new-harness-composer'));
final _task = find.byKey(const ValueKey('new-harness-task'));
final _machine = find.byKey(const ValueKey('new-harness-machine'));
final _close = find.byKey(const ValueKey('new-harness-close'));
final _chooser = find.byKey(const ValueKey('new-harness-chooser-surface'));
final _query = find.byKey(const ValueKey('new-harness-query'));

bool _focused(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final element = tester.element(finder);
  var found = FocusManager.instance.primaryFocus?.context == element;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
    ancestor,
  ) {
    if (ancestor == element) found = true;
    return !found;
  });
  return found;
}

Future<void> _focus(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 16 && !_focused(tester, finder); attempt++) {
    await key(tester, LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  expect(
    _focused(tester, finder),
    isTrue,
    reason: '$finder is reachable by Tab',
  );
}

void _expectReadingOrder(Rect before, Rect after) {
  expect(
    before.bottom <= after.top ||
        (before.center.dy - after.center.dy).abs() <= 1 &&
            before.right < after.left,
    isTrue,
    reason: 'Settings retain reading order when wider fonts wrap the row',
  );
}

Future<_ReviewFixture> _mount(
  WidgetTester tester, {
  String engine = 'codex',
  String machineName = 'office',
  String folder = '/work/autonomous-harness',
  bool git = true,
  List<String> branchNames = const ['main', 'feature/review'],
  Size size = const Size(1200, 800),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  NewHarnessDraft? draft,
  FutureOr<void> Function(_ReviewFixture)? onBrowse,
}) async {
  final app = _ReviewApp(
    machineName: machineName,
    git: git,
    branchNames: branchNames,
  );
  final box = NewHarnessController(
    app,
    machineId: 'review',
    engine: engine,
    folder: folder,
    draft: draft,
  );
  final fixture = _ReviewFixture(app, box, MemoryKeymap());
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
      theme: grid
          .buildAppTheme(brightness: brightness)
          .copyWith(platform: TargetPlatform.macOS),
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
                    child: DesktopDialogBackdrop(
                      onDismiss: () =>
                          fixture.form.currentState?.dismissFromOutside(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: NewHarnessForm(
                      key: fixture.form,
                      controller: box,
                      desktop: true,
                      onBrowse: onBrowse == null
                          ? null
                          : () => onBrowse(fixture),
                      onClose: () => fixture.closes++,
                      onCreated: () => fail('The fake launch must not succeed'),
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

void main() {
  final renderDir = Platform.environment['COMPOSER_LAYOUT_RENDER_DIR'];
  setUpAll(() async {
    if (renderDir != null) await loadPreviewFonts();
  });

  Future<void> capture(
    WidgetTester tester,
    _ReviewFixture fixture,
    String name,
  ) async {
    if (renderDir == null) return;
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    final boundary =
        fixture.image.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    try {
      final images = tester.widgetList<Image>(
        find.descendant(
          of: find.byKey(fixture.image),
          matching: find.byType(Image),
        ),
      );
      await tester.runAsync(() async {
        await Future.wait([
          for (final image in images)
            precacheImage(image.image, fixture.image.currentContext!),
        ]);
      });
      // Changing the debug flag does not invalidate an already painted layer.
      // Repaint the physical shapes so captures contain actual soft shadows.
      repaint(boundary);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(renderDir)..createSync(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousDisableShadows;
      repaint(boundary);
      await tester.pump();
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'wide composer follows the reviewed ${brightness.name} layout',
      (tester) async {
        final fixture = await _mount(tester, brightness: brightness);
        final surface = tester.getRect(_surface);
        final composer = tester.getRect(_composer);
        final agent = tester.getRect(_field('agent'));
        final machine = tester.getRect(_machine);
        final repo = tester.getRect(_field('project'));
        final action = tester.getRect(_field('start'));
        final model = tester.getRect(_field('model'));
        final approvals = tester.getRect(_field('approvals'));
        final profile = tester.getRect(_field('profile'));
        final worktree = tester.getRect(_field('worktree'));
        final branch = tester.getRect(_field('branch'));

        expect(surface.width, 860);
        expect(agent.right, lessThan(machine.left));
        expect(machine.right, lessThan(repo.left));
        expect(agent.center.dy, closeTo(repo.center.dy, 1));
        expect(repo.bottom, lessThan(composer.top));
        expect(composer.contains(action.topLeft), isTrue);
        expect(composer.contains(action.bottomRight), isTrue);
        expect(action.right, greaterThan(composer.right - 28));
        expect(action.bottom, greaterThan(composer.bottom - 28));
        expect(model.top, greaterThan(composer.bottom));
        _expectReadingOrder(model, approvals);
        _expectReadingOrder(approvals, profile);
        expect(profile.right, lessThan(worktree.left));
        expect(worktree.right, lessThanOrEqualTo(branch.left));
        expect(worktree.center.dy, closeTo(branch.center.dy, 1));
        expect(branch.right, greaterThan(surface.center.dx));
        expect(find.text('New harness'), findsOneWidget);
        expect(
          tester.widget<TextField>(_task).decoration!.hintText,
          'What’s next?',
        );
        expect(find.text('Options'), findsNothing);
        expect(find.text('Add task'), findsNothing);
        expect(_field('advanced'), findsNothing);
        expect(_focused(tester, _field('start')), isTrue);
        expect(fixture.app.launches, isEmpty);
        expect(tester.takeException(), isNull);
        await capture(tester, fixture, 'composer-${brightness.name}');
      },
    );
  }

  testWidgets('footer controls stay text-only and use a stable focus fill', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    Material buttonMaterial(Finder control) => tester.widget<Material>(
      find.descendant(of: control, matching: find.byType(Material)).first,
    );
    for (final name in [
      'model',
      'approvals',
      'profile',
      'worktree',
      'branch',
    ]) {
      final control = _field(name);
      expect(
        find.descendant(of: control, matching: find.byType(Icon)),
        findsNothing,
      );
      final before = tester.getRect(control);
      final resting = buttonMaterial(control);
      await _focus(tester, control);
      final focused = buttonMaterial(control);
      expect(focused.color, isNot(resting.color));
      expect(tester.getRect(control), before);
      final restingShape = resting.shape! as OutlinedBorder;
      final focusedShape = focused.shape! as OutlinedBorder;
      expect(focusedShape.side, restingShape.side);
      expect(focusedShape.side.width, lessThanOrEqualTo(1));
    }
    expect(find.text('Worktree on'), findsOneWidget);
    expect(fixture.app.launches, isEmpty);
  });

  testWidgets('agent identity is shown by the Codex and Claude marks', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    Finder mark(Finder control) =>
        find.descendant(of: control, matching: find.byType(EngineMark));
    expect(tester.widget<EngineMark>(mark(_field('agent'))).engine, 'codex');
    expect(
      find.descendant(
        of: _field('agent'),
        matching: find.byKey(const ValueKey('engine-icon-codex')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _field('agent'),
        matching: find.byIcon(Icons.code_rounded),
      ),
      findsNothing,
    );
    await tester.tap(_field('agent'));
    await tester.pumpAndSettle();
    final codex = find.byKey(const ValueKey('new-harness-option-codex'));
    final claude = find.byKey(const ValueKey('new-harness-option-claude'));
    expect(tester.widget<EngineMark>(mark(codex)).engine, 'codex');
    expect(tester.widget<EngineMark>(mark(claude)).engine, 'claude');
    await tester.tap(claude);
    await tester.pumpAndSettle();
    expect(tester.widget<EngineMark>(mark(_field('agent'))).engine, 'claude');
    expect(
      find.descendant(
        of: _field('agent'),
        matching: find.byKey(const ValueKey('engine-icon-claude')),
      ),
      findsOneWidget,
    );
    expect(_field('profile'), findsNothing);
    expect(fixture.app.launches, isEmpty);
    await capture(tester, fixture, 'composer-claude-dark');
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'machine and repo menus fit their ${brightness.name} contents',
      (tester) async {
        final fixture = await _mount(
          tester,
          brightness: brightness,
          onBrowse: (_) {},
        );
        for (final (trigger, field, name, maximumHeight) in [
          (_machine, NewHarnessField.machine, 'machine', 160.0),
          (_field('project'), NewHarnessField.projectMenu, 'repo', 280.0),
        ]) {
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          expect(fixture.box.field, field);
          expect(_chooser, findsOneWidget);
          expect(_query.hitTestable(), findsOneWidget);
          expect(
            find.descendant(of: _chooser, matching: find.byType(IconButton)),
            findsNothing,
          );
          expect(find.text('Choose machine'), findsNothing);
          expect(find.text('Choose repo'), findsNothing);
          expect(
            find.descendant(of: _chooser, matching: find.textContaining('Esc')),
            findsNothing,
          );
          final menu = tester.getRect(_chooser);
          expect(menu.width, 380);
          expect(menu.height, lessThan(maximumHeight));
          final rows = find.descendant(
            of: _chooser,
            matching: find.byWidgetPredicate((widget) {
              final key = widget.key;
              return widget is Semantics &&
                  key is ValueKey<String> &&
                  key.value.startsWith('new-harness-option-');
            }),
          );
          final lastBottom = rows
              .evaluate()
              .map((element) {
                return tester.getRect(find.byWidget(element.widget)).bottom;
              })
              .reduce((a, b) => a > b ? a : b);
          expect(menu.bottom - lastBottom, inInclusiveRange(0, 12));
          if (field == NewHarnessField.machine) {
            final row = find.byKey(const ValueKey('new-harness-option-review'));
            expect(
              find.descendant(of: row, matching: find.text('office')),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: row,
                matching: find.byIcon(Icons.laptop_mac_rounded),
              ),
              findsNothing,
            );
          }
          await capture(tester, fixture, '$name-menu-${brightness.name}');
          await key(tester, LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_chooser, findsNothing);
          expect(_focused(tester, trigger), isTrue);
        }
        expect(fixture.closes, 0);
        expect(fixture.app.launches, isEmpty);
      },
    );
  }

  for (final (size, scale, name) in [
    (const Size(1200, 800), 1.0, 'wide'),
    (const Size(600, 520), 1.6, 'narrow'),
  ]) {
    testWidgets(
      'a long branch keeps one baseline with Worktree in $name layout',
      (tester) async {
        const branch =
            'feature/refine-machine-and-repository-choice-with-a-very-long-branch-name';
        final fixture = await _mount(
          tester,
          size: size,
          scale: scale,
          branchNames: ['main', branch],
        );
        await _focus(tester, _field('branch'));
        await key(tester, LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.enterText(_query, branch);
        await key(tester, LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final worktreeBounds = tester.getRect(_field('worktree'));
        final branchBounds = tester.getRect(_field('branch'));
        expect(worktreeBounds.center.dy, closeTo(branchBounds.center.dy, 1));
        expect(worktreeBounds.right, lessThanOrEqualTo(branchBounds.left));
        expect(_field('branch').hitTestable(), findsOneWidget);
        final branchText = tester.widget<Text>(
          find.descendant(of: _field('branch'), matching: find.byType(Text)),
        );
        expect(branchText.maxLines, 1);
        expect(branchText.overflow, TextOverflow.ellipsis);
        expect(branchText.semanticsLabel, contains(branch));
        await tester.tap(_field('worktree'));
        await tester.pumpAndSettle();
        expect(find.text('Worktree off'), findsOneWidget);
        expect(tester.getRect(_field('worktree')), worktreeBounds);
        expect(tester.getRect(_field('branch')), branchBounds);
        expect(fixture.box.branchRef, 'refs/heads/$branch');
        expect(fixture.box.worktree, isFalse);
        expect(fixture.app.launches, isEmpty);
        expect(tester.takeException(), isNull);
        await capture(tester, fixture, 'long-branch-$name');
      },
    );
  }

  testWidgets(
    'every visible control takes one Tab stop with no hidden options',
    (tester) async {
      final fixture = await _mount(tester);
      final cycle = [
        _field('agent'),
        _machine,
        _field('project'),
        _task,
        _field('model'),
        _field('approvals'),
        _field('profile'),
        _field('worktree'),
        _field('branch'),
        _close,
        _field('start'),
      ];
      expect(_focused(tester, _field('start')), isTrue);
      for (final target in cycle) {
        await key(tester, LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          _focused(tester, target),
          isTrue,
          reason:
              'Expected $target; focus is '
              '${FocusManager.instance.primaryFocus?.debugLabel}',
        );
      }
      for (final target in cycle.reversed.skip(1)) {
        await key(tester, LogicalKeyboardKey.tab, shift: true);
        await tester.pumpAndSettle();
        expect(_focused(tester, target), isTrue);
      }
      expect(_chooser, findsNothing);
      expect(fixture.app.launches, isEmpty);
    },
  );

  testWidgets('direct controls expose names and the worktree checked state', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final semantics = tester.ensureSemantics();
    for (final label in [
      'Agent, Codex',
      'Machine, office',
      'Repo, office:/work/autonomous-harness',
      'Model, OpenAI',
      'Approvals, Auto-approve',
      'Profile, Default',
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    }
    var worktree = tester.getSemantics(_field('worktree')).getSemanticsData();
    expect(worktree.flagsCollection.isChecked, ui.CheckedState.isTrue);
    await _focus(tester, _field('worktree'));
    await key(tester, LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    worktree = tester.getSemantics(_field('worktree')).getSemanticsData();
    expect(worktree.flagsCollection.isChecked, ui.CheckedState.isFalse);
    expect(fixture.box.worktree, isFalse);
    expect(fixture.app.launches, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'initial Return creates an empty session with reviewed defaults',
    (tester) async {
      final fixture = await _mount(tester);
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fixture.app.launches, hasLength(1));
      final launch = fixture.app.launches.single;
      expect(launch['machine'], 'review');
      expect(launch['engine'], 'codex');
      expect(launch['prompt'], isNull);
      expect(launch['permissions'], 'auto');
      final folder = launch['projectFolder']! as ProjectFolderRequest;
      expect(folder.gitSource, '/work/autonomous-harness');
      expect(folder.createsWorktree, isTrue);
      expect(folder.branchRef, 'refs/heads/main');
      expect(fixture.closes, 0);
    },
  );

  testWidgets(
    'editor Enter stays multiline and Cmd-Return sends the exact draft',
    (tester) async {
      final fixture = await _mount(tester);
      const task =
          'Explore the current flow.\nThen discuss a plan — no changes yet.';
      await tester.enterText(_task, task);
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.app.launches, isEmpty);
      expect(_focused(tester, _task), isTrue);
      // Native text insertion is owned by the editing channel, not sendKeyEvent.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '$task\n',
          selection: TextSelection.collapsed(offset: task.length + 1),
        ),
      );
      await tester.pump();
      expect(fixture.box.task, '$task\n');
      const completeTask = '$task\nCompare the alternatives.';
      await tester.enterText(_task, completeTask);
      await key(tester, LogicalKeyboardKey.enter, cmd: true);
      await tester.pumpAndSettle();
      expect(fixture.app.launches, hasLength(1));
      expect(fixture.app.launches.single['prompt'], completeTask);
    },
  );

  testWidgets(
    'empty editor shows the working launch key after focus and remapping',
    (tester) async {
      final fixture = await _mount(tester);
      Finder hint(String label) =>
          find.descendant(of: _field('start'), matching: find.text(label));
      expect(hint('↵'), findsOneWidget);
      await tester.tap(_task);
      await tester.pumpAndSettle();
      expect(hint('↵'), findsNothing);
      expect(hint('⌘↵'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(fixture.app.launches, isEmpty);

      fixture.map.apply(
        '{"bindings":[{"keys":"cmd+enter","command":null,"when":"picker"}]}',
      );
      await tester.pumpAndSettle();
      expect(hint('⌘↵'), findsNothing);
      await key(tester, LogicalKeyboardKey.enter, cmd: true);
      expect(fixture.app.launches, isEmpty);

      fixture.map.apply(
        '{"bindings":[{"keys":"f8","command":"picker.add_here","when":"picker"},'
        '{"keys":"cmd+enter","command":null,"when":"picker"}]}',
      );
      await tester.pumpAndSettle();
      expect(hint('F8'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.f8);
      await tester.pumpAndSettle();
      expect(fixture.app.launches, hasLength(1));
      expect(fixture.app.launches.single['prompt'], isNull);
    },
  );

  testWidgets(
    'each menu dismisses by mouse without dismissing or editing the form',
    (tester) async {
      final fixture = await _mount(tester);
      const draft = 'Keep this while exploring the settings';
      await tester.enterText(_task, draft);
      for (final trigger in [
        _field('agent'),
        _machine,
        _field('project'),
        _field('model'),
        _field('approvals'),
        _field('profile'),
        _field('branch'),
      ]) {
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(_chooser, findsOneWidget);
        await tester.tapAt(const Offset(30, 30));
        await tester.pumpAndSettle();
        expect(_chooser, findsNothing, reason: '$trigger closes one level');
        expect(_focused(tester, trigger), isTrue);
        expect(fixture.closes, 0);
        expect(fixture.box.task, draft);
        expect(fixture.app.launches, isEmpty);
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(fixture.closes, 1);
      expect(fixture.box.draft.task, draft);
    },
  );

  testWidgets(
    'approval and branch choices require a separate launch activation',
    (tester) async {
      final fixture = await _mount(tester);
      await _focus(tester, _field('approvals'));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(_query, 'Full access');
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fixture.box.mode, 'full');
      expect(_focused(tester, _field('approvals')), isTrue);
      expect(fixture.app.launches, isEmpty);

      await _focus(tester, _field('worktree'));
      await key(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.tab);
      expect(_focused(tester, _field('branch')), isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(_query, 'feature/review');
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_focused(tester, _field('branch')), isTrue);
      expect(fixture.app.launches, isEmpty);
      await tester.tap(_field('start'));
      await tester.pumpAndSettle();
      expect(fixture.app.launches, hasLength(1));
      final launch = fixture.app.launches.single;
      expect(launch['permissions'], 'full');
      final folder = launch['projectFolder']! as ProjectFolderRequest;
      expect(folder.createsWorktree, isFalse);
      expect(folder.branchRef, 'refs/heads/feature/review');
    },
  );

  testWidgets(
    'switching agents removes inapplicable controls and their Tab stops',
    (tester) async {
      final fixture = await _mount(tester);
      await tester.enterText(_task, 'Keep a draft while changing agents');
      await tester.tap(_field('agent'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-harness-option-claude')));
      await tester.pumpAndSettle();
      expect(_field('profile'), findsNothing);
      expect(_field('model'), findsOneWidget);
      expect(_field('approvals'), findsOneWidget);
      await _focus(tester, _field('approvals'));
      await key(tester, LogicalKeyboardKey.tab);
      expect(_focused(tester, _field('worktree')), isTrue);

      await tester.tap(_field('agent'));
      await tester.pumpAndSettle();
      await tester.enterText(_query, 'Terminal');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('new-harness-option-terminal')),
      );
      await tester.pumpAndSettle();
      expect(fixture.box.engine, 'terminal');
      for (final name in [
        'model',
        'approvals',
        'profile',
        'worktree',
        'branch',
      ]) {
        expect(_field(name), findsNothing);
      }
      expect(tester.widget<TextField>(_task).readOnly, isTrue);
      await _focus(tester, _field('project'));
      await key(tester, LogicalKeyboardKey.tab);
      expect(_focused(tester, _close), isTrue);
      expect(fixture.box.task, 'Keep a draft while changing agents');
      expect(fixture.app.launches, isEmpty);
    },
  );

  testWidgets(
    'Open Folder invokes the picker directly and cancellation keeps context',
    (tester) async {
      var browses = 0;
      var accept = false;
      final fixture = await _mount(
        tester,
        onBrowse: (fixture) {
          browses++;
          expect(fixture.box.machineId, 'review');
          if (accept) fixture.box.setFolder('/work/another-repo');
        },
      );
      await tester.enterText(
        _task,
        'Preserve the draft through native browsing',
      );
      await tester.tap(_field('project'));
      await tester.pumpAndSettle();
      final open = find.byKey(
        const ValueKey('new-harness-option-project:existing'),
      );
      expect(
        find.descendant(of: open, matching: find.text('Open Folder…')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: open,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
        reason: 'The native picker opens directly instead of a submenu',
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(browses, 1);
      expect(_chooser, findsOneWidget);
      expect(fixture.box.field, NewHarnessField.projectMenu);
      expect(fixture.box.project.folder, '/work/autonomous-harness');
      accept = true;
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(browses, 2);
      expect(_chooser, findsNothing);
      expect(fixture.box.project.folder, '/work/another-repo');
      expect(_focused(tester, _field('project')), isTrue);
      expect(fixture.box.task, 'Preserve the draft through native browsing');
      expect(fixture.closes, 0);
      expect(fixture.app.launches, isEmpty);
    },
  );

  testWidgets('folder browsing can retry after failure from its path prompt', (
    tester,
  ) async {
    var browses = 0;
    final fixture = await _mount(
      tester,
      onBrowse: (fixture) {
        browses++;
        if (browses == 1) throw const FileSystemException('Synthetic failure');
        if (browses == 3) fixture.box.setFolder('/work/retry-repo');
      },
    );
    fixture.map.apply(
      '{"bindings":[{"keys":"f7","command":"creation.project_browse","when":"picker"}]}',
    );
    await tester.enterText(_task, 'Keep this question through folder recovery');
    await tester.tap(_field('project'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('new-harness-option-project:existing')),
    );
    await tester.pumpAndSettle();
    expect(browses, 1);
    expect(fixture.box.field, NewHarnessField.project);
    expect(find.text('Could not browse folders. Try again.'), findsWidgets);
    expect(_focused(tester, _query), isTrue);

    // A failed native picker leaves a usable path prompt. Its browse shortcut
    // retries that prompt directly, instead of opening another machine step.
    await key(tester, LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();
    expect(browses, 2);
    expect(fixture.box.field, NewHarnessField.project);
    expect(_chooser, findsOneWidget);
    expect(_focused(tester, _query), isTrue);
    expect(fixture.box.project.folder, '/work/autonomous-harness');

    await key(tester, LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();
    expect(browses, 3);
    expect(_chooser, findsNothing);
    expect(fixture.box.project.folder, '/work/retry-repo');
    expect(fixture.box.task, 'Keep this question through folder recovery');
    expect(fixture.closes, 0);
    expect(fixture.app.launches, isEmpty);
  });

  testWidgets(
    'a footer menu opens above its control when the draft grows tall',
    (tester) async {
      final fixture = await _mount(
        tester,
        size: const Size(900, 1000),
        scale: 1.4,
        branchNames: [
          'main',
          'feature/review',
          for (var i = 0; i < 20; i++) 'feature/iteration-$i',
        ],
      );
      const draft =
          'First, inspect the current flow.\n'
          'Discuss the constraints.\n'
          'Compare the possible designs.\n'
          'Keep existing shortcuts.\n'
          'Make cancellation predictable.\n'
          'Check the resulting interaction.\n'
          'Then tell me what you recommend.';
      await tester.enterText(_task, draft);
      await _focus(tester, _field('branch'));
      final branch = tester.getRect(_field('branch'));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final menu = tester.getRect(_chooser);
      expect(menu.bottom, closeTo(branch.top - 8, 1));
      expect(menu.top, greaterThanOrEqualTo(36));
      expect(menu.right, lessThanOrEqualTo(864));
      expect(_query.hitTestable(), findsOneWidget);
      await tester.enterText(_query, 'feature/review');
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_chooser, findsNothing);
      expect(_focused(tester, _field('branch')), isTrue);
      expect(fixture.box.branchRef, 'refs/heads/feature/review');
      expect(fixture.box.task, draft);
      expect(fixture.app.launches, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final git in [true, false]) {
    testWidgets('Terminal Options shortcut reaches Repo for git=$git', (
      tester,
    ) async {
      final fixture = await _mount(tester, engine: 'terminal', git: git);
      fixture.map.apply(
        '{"bindings":[{"keys":"f7","command":"creation.options","when":"picker"}]}',
      );
      await key(tester, LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(_chooser, findsOneWidget);
      expect(fixture.box.field, NewHarnessField.projectMenu);
      expect(
        find.byKey(const ValueKey('new-harness-option-project:existing')),
        findsOneWidget,
      );
      expect(_focused(tester, _query), isTrue);
      expect(_field('model'), findsNothing);
      expect(_field('branch'), findsNothing);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_chooser, findsNothing);
      expect(_focused(tester, _field('project')), isTrue);

      // The older default shortcut follows the same visible fallback.
      await key(tester, LogicalKeyboardKey.period, cmd: true);
      await tester.pumpAndSettle();
      expect(fixture.box.field, NewHarnessField.projectMenu);
      expect(_chooser, findsOneWidget);
      expect(fixture.closes, 0);
      expect(fixture.app.launches, isEmpty);
    });
  }

  testWidgets(
    'restored drafts keep text and settings visible and focus the editor',
    (tester) async {
      final original = await _mount(tester);
      await tester.enterText(_task, 'A saved question, ready to continue');
      await tester.tap(_field('worktree'));
      await tester.tap(_field('profile'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('new-harness-option-profile:/profiles/work')),
      );
      await tester.pumpAndSettle();
      final draft = original.box.draft;
      await tester.pumpWidget(const SizedBox());
      final restored = await _mount(tester, draft: draft);
      expect(_focused(tester, _task), isTrue);
      expect(tester.widget<TextField>(_task).controller!.text, draft.task);
      expect(restored.box.worktree, isFalse);
      expect(restored.box.profileLabel, 'Work');
      expect(find.text('Work'), findsOneWidget);
      expect(_field('profile'), findsOneWidget);
      expect(_field('branch'), findsOneWidget);
      expect(restored.app.launches, isEmpty);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'long controls remain reachable at 600x520 ${brightness.name} scale=$scale',
        (tester) async {
          final fixture = await _mount(
            tester,
            machineName: 'Office Mac development workstation with a long name',
            folder: '/work/a-repository-with-a-long-but-recognizable-name',
            size: const Size(600, 520),
            scale: scale,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          expect(tester.getSize(_surface).width, lessThanOrEqualTo(552));
          await tester.enterText(
            _task,
            'A question with enough text to span several lines in a narrow '
            'window. Preserve the same controls at enlarged text sizes.',
          );
          for (final control in [
            _field('model'),
            _field('approvals'),
            _field('profile'),
            _field('worktree'),
            _field('branch'),
            _field('start'),
          ]) {
            await _focus(tester, control);
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            expect(control.hitTestable(), findsOneWidget);
            final rect = tester.getRect(control);
            expect(rect.left, greaterThanOrEqualTo(24));
            expect(rect.right, lessThanOrEqualTo(576));
            expect(tester.takeException(), isNull);
          }
          await capture(tester, fixture, 'narrow-${brightness.name}-$scale');
          expect(fixture.app.launches, isEmpty);
        },
      );
    }
  }
}
