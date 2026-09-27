import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/harness_sessions.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import '../state/welcome_sessions.dart';
import 'engine_identity.dart';
import '../shared/theme/appearance_prefs_store.dart';
import '../shared/theme/harness_background.dart';
import 'swarm_wallpaper.dart';
import 'terminal_text_action.dart';
import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import '../shortcuts/keymap_commands.dart';
import '../terminal/terminal_text.dart';

/// A quiet terminal welcome. Opening a command is always an explicit action.
///
/// With [app], it also offers what to pick up: the harnesses you were just
/// with and the Claude Code and Codex conversations on your machines that
/// Harness did not start ([WelcomeSessions]), numbered 1–9 like the terminal
/// client's home. [onOpen] opens one in this tab, as Cmd-P would.
class WorkspaceWelcome extends StatefulWidget {
  const WorkspaceWelcome({
    super.key,
    required this.onCommand,
    this.app,
    this.projects = const [],
    this.onOpen,
  });

  final ValueChanged<String> onCommand;
  final AppNotifier? app;
  final List<SavedSwarmProject> projects;
  final ValueChanged<SwarmDestination>? onOpen;

  @override
  State<WorkspaceWelcome> createState() => _WorkspaceWelcomeState();
}

class _WorkspaceWelcomeState extends State<WorkspaceWelcome> {
  WelcomeSessions? _sessions;
  int _cursor = 0;

  ValueChanged<String> get onCommand => widget.onCommand;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    if (app != null && widget.onOpen != null) {
      _sessions = WelcomeSessions(app, projects: widget.projects)
        ..addListener(_changed);
      _sessions!.load();
      app.addListener(_appChanged);
    }
  }

  void _appChanged() => _sessions?.appChanged();

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_sessions != null) widget.app?.removeListener(_appChanged);
    _sessions
      ?..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _open(int index) {
    final rows = _sessions?.rows ?? const [];
    if (index < 0 || index >= rows.length) return;
    widget.onOpen?.call(rows[index]);
  }

  /// A tab with nothing in it has no pane to take keys: plain ones work here,
  /// as on the terminal client's home. Anything else goes on to the shortcuts.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _sessions?.rows ?? const [];
    if (rows.isEmpty ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final digit = key.keyLabel.length == 1 ? int.tryParse(key.keyLabel) : null;
    if (digit != null && digit >= 1 && digit <= rows.length) {
      _open(digit - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _cursor = (_cursor + 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _cursor = (_cursor - 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _open(_cursor.clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static const _actions = [
    ('agent.new', 'Start an agent'),
    ('harnesses.list', 'Manage all your agents'),
    ('models.list', 'Deploy a local model'),
    ('machines.list', 'Manage all your machines'),
    ('app.store', 'Build beyond code'),
  ];

  @override
  Widget build(BuildContext context) {
    TerminalFontScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([terminalFontStore, appearancePrefsStore]),
      builder: (context, _) => _buildWelcome(context),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    grid.AppTheme.watch(context);
    final palette = grid.AppTheme.palette.value;
    final background = appearancePrefsStore.value.background;
    final hasArtwork = background != HarnessBackground.plain;
    final ink = hasArtwork
        ? const Color(0xffdededb)
        : palette.foreground.withValues(alpha: .75);
    // The welcome surface uses a dark workspace palette in both theme modes.
    const accent = Color(0xffa5d786);
    // The page stands where a terminal will, so it is set like one: the
    // terminal's face at the terminal's size, following ⌘+ and ⌘−.
    final style = terminalTextStyle(
      color: ink,
      fontWeight: FontWeight.w400,
      height: 1.5,
    );
    final keymap = KeymapTheme.of(context)?.current ?? harnessDefaultKeymap;
    final rows = [
      for (final (command, description) in _actions)
        (
          command: command,
          description: description,
          hint: keymap
              .bindingsFor(KeymapContext.workspace)
              .where((binding) => binding.command == command)
              .map(describeKeyBinding)
              .firstOrNull,
        ),
    ];
    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final keyWidth = rows
        .map((row) => widthOf('${row.hint ?? ''}    '))
        .reduce((a, b) => a > b ? a : b);
    final descriptionWidth = rows
        .map((row) => widthOf(row.description))
        .reduce((a, b) => a > b ? a : b);
    final line = MediaQuery.textScalerOf(context).scale(style.fontSize!) * 1.5;
    final cell = widthOf('M');
    final listWidth = (cell * 84).clamp(
      keyWidth + descriptionWidth,
      double.infinity,
    );
    final sessions = _sessionsSection(
      style: style,
      ink: ink,
      accent: accent,
      cell: cell,
    );
    final footerInset = line + 52;
    return Focus(
      autofocus: _sessions != null,
      onKeyEvent: _key,
      child: Material(
        key: const ValueKey('workspace-welcome'),
        color: grid.AppPalette.swarmWelcome,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: const ValueKey('welcome-wallpaper'),
              child: SwarmWallpaper(background: background),
            ),
            LayoutBuilder(
              // Keep the text centered when it fits, but let large text scroll
              // above the fixed Customize button rather than underneath it.
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.only(bottom: footerInset),
                child: SingleChildScrollView(
                  key: const ValueKey('welcome-scroll'),
                  padding: EdgeInsets.fromLTRB(24, footerInset + 24, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - footerInset * 2 - 48)
                          .clamp(0, double.infinity),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: sessions == null
                              ? keyWidth + descriptionWidth
                              : listWidth,
                        ),
                        child: DefaultTextStyle(
                          style: style,
                          textAlign: TextAlign.center,
                          child: Column(
                            key: const ValueKey('workspace-welcome-text'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Harness like a boss.',
                                key: const ValueKey('welcome-tagline'),
                              ),
                              SizedBox(height: line),
                              if (sessions != null) ...[
                                sessions,
                                SizedBox(height: line),
                              ],
                              for (final row in rows)
                                Center(
                                  child: SizedBox(
                                    width: keyWidth + descriptionWidth,
                                    child: TextButton(
                                      key: ValueKey('welcome-${row.command}'),
                                      onPressed: () => onCommand(row.command),
                                      style: TextButton.styleFrom(
                                        foregroundColor: ink,
                                        textStyle: style,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: const RoundedRectangleBorder(),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: keyWidth,
                                            child: Text(
                                              row.hint ?? '',
                                              style: TextStyle(color: accent),
                                              textAlign: TextAlign.left,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              row.description,
                                              textAlign: TextAlign.left,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: 16,
              child: TerminalTextAction(
                key: const ValueKey('welcome-customize'),
                onPressed: () => onCommand('app.customize'),
                label: 'Customize Harness',
                overArtwork: hasArtwork,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What to pick up, numbered: null when there is nothing to offer.
  Widget? _sessionsSection({
    required TextStyle style,
    required Color ink,
    required Color accent,
    required double cell,
  }) {
    final sessions = _sessions;
    if (sessions == null) return null;
    final rows = sessions.rows;
    final muted = ink.withValues(alpha: .55);
    if (rows.isEmpty) {
      return sessions.loading
          ? Text('Finding your sessions…', style: TextStyle(color: muted))
          : null;
    }
    final app = widget.app!;
    final many = app.searchableMachineIds.length > 1;
    return Column(
      key: const ValueKey('welcome-sessions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick up where you left off',
          textAlign: TextAlign.left,
          style: TextStyle(color: muted),
        ),
        for (final (index, row) in rows.indexed)
          _sessionRow(
            index,
            row,
            app: app,
            style: style,
            ink: ink,
            muted: muted,
            accent: accent,
            cell: cell,
            showMachine: many,
          ),
      ],
    );
  }

  Widget _sessionRow(
    int index,
    SwarmDestination row, {
    required AppNotifier app,
    required TextStyle style,
    required Color ink,
    required Color muted,
    required Color accent,
    required double cell,
    required bool showMachine,
  }) {
    final machine = app.stateOf(row.machineId ?? '');
    final agent = row.agentId == null
        ? null
        : machine?.agents.where((agent) => agent.id == row.agentId).firstOrNull;
    final waiting = agent == null ? null : machine?.blockedAgents[agent.id];
    final working =
        agent != null && machine!.processingAgentIds.contains(agent.id);
    final external = row.external;
    final (dot, dotColor) = external != null
        ? (' ', muted)
        : waiting != null
        ? ('●', const Color(0xffe9bf79))
        : working
        ? ('●', const Color(0xffadc5eb))
        : agent?.isStopped == true
        ? ('○', muted)
        : ('●', const Color(0xff9abea5));
    final folder = external?.cwd
        .split('/')
        .where((part) => part.isNotEmpty)
        .lastOrNull;
    final detail = external != null
        ? [external.originLabel, ?folder, 'not in Harness'].join(' · ')
        : waiting?.prompt ??
              (agent == null ? null : machine?.projectOf(agent)?.label) ??
              '';
    final at = row.lastActivityAt;
    final readAt = _sessions!.readAt;
    final age = at == null
        ? ''
        : readAt.difference(at).inMinutes < 1
        ? 'now'
        : harnessActivityAge(at, readAt);
    final right = [
      if (showMachine && machine != null) machine.machine.displayName,
      age,
    ].where((part) => part.isNotEmpty).join('  ');
    final selected = index == _cursor;
    return TextButton(
      key: ValueKey('welcome-session-${row.id}'),
      onPressed: () => _open(index),
      style: TextButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: selected
            ? Colors.white.withValues(alpha: .07)
            : Colors.transparent,
        textStyle: style,
        padding: const EdgeInsets.symmetric(vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      child: Row(
        children: [
          SizedBox(
            width: cell * 3,
            child: Text('${index + 1}', style: TextStyle(color: accent)),
          ),
          SizedBox(
            width: cell * 2,
            child: Text(dot, style: TextStyle(color: dotColor)),
          ),
          Padding(
            padding: EdgeInsets.only(right: cell),
            child: EngineMark(
              engine: agent?.identityEngine ?? row.engine,
              displayName: agent?.identityDisplayName,
              size: (style.fontSize ?? 13) * 1.1,
            ),
          ),
          SizedBox(
            width: cell * 30,
            child: Text(
              row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: cell * 2),
          Expanded(
            child: Text(
              detail.replaceAll('\n', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: waiting != null ? const Color(0xffe9bf79) : muted,
              ),
            ),
          ),
          if (right.isNotEmpty) ...[
            SizedBox(width: cell * 2),
            Text(right, style: TextStyle(color: muted)),
          ],
        ],
      ),
    );
  }
}
