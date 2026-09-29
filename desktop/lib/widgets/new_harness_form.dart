import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' show TerminalTheme;

import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import '../core/dsh_catalog.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';
import '../state/new_harness.dart';
import '../state/device_form.dart';
import 'box_chrome.dart' show kTerminalCornerRadius, terminalPaneBorder;
import 'dsh_install_panel.dart' show describeInstallFailure;
import 'desktop_chrome.dart';

/// Agent, Project, and collapsed Options in a compact terminal grid.
/// Enter on the selected launch action starts with the displayed defaults.
/// Selecting a field reveals its chooser beside the centered form.
class NewHarnessForm extends StatefulWidget {
  const NewHarnessForm({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onCreated,
    this.onBrowse,
    this.onStore,
    this.onLinkProfile,
    this.onNeedsForm,
    this.devicePort,
    this.desktop = false,
  });

  final NewHarnessController controller;
  final VoidCallback onClose;
  final VoidCallback onCreated;
  final FutureOr<void> Function()? onBrowse;
  final VoidCallback? onStore, onLinkProfile, onNeedsForm;
  final DeviceFormPort? devicePort;
  final bool desktop;

  @override
  State<NewHarnessForm> createState() => NewHarnessFormState();
}

enum _Row {
  agent,
  project,
  advanced,
  model,
  approvals,
  profile,
  branch,
  worktree,
  start,
}

/// The workspace backdrop shares the form's dismissal hierarchy. A chooser
/// consumes a dismissal before the composer (and its draft) can be dismissed.
class NewHarnessFormState extends State<NewHarnessForm> {
  NewHarnessController get box => widget.controller;
  final _focus = FocusNode(debugLabel: 'new-harness-form');
  final _inputFocus = FocusNode(debugLabel: 'new-harness-query');
  final _queryText = TextEditingController();
  late final _taskText = TextEditingController(text: box.task);
  final _taskFocus = FocusNode(debugLabel: 'New harness task');
  final _taskToggleFocus = FocusNode(debugLabel: 'New harness add task');
  late bool _taskExpanded = box.task.isNotEmpty;
  bool get _expanded => _taskExpanded || box.advancedOpen;
  bool get _desktopStartEnabled =>
      !box.busy &&
      !box.linkingProfile &&
      box.requiredChoice == null &&
      !box.taskTooLong;
  FocusNode get _desktopDefaultFocus => _taskExpanded
      ? _taskFocus
      : _desktopStartEnabled
      ? _desktopFocus[_Row.start]!
      : _focus;
  final _dialogScope = FocusScopeNode(
    debugLabel: 'New harness dialog',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final _desktopCanvasKey = GlobalKey();
  final _desktopAnchors = {for (final row in _Row.values) row: GlobalKey()};
  final _desktopFocus = {
    for (final row in _Row.values)
      row: FocusNode(debugLabel: 'New harness ${row.name}'),
  };
  final _machineAnchor = GlobalKey();
  final _machineFocus = FocusNode(debugLabel: 'New harness machine');
  FocusNode? _chooserOrigin;
  GlobalKey? _chooserAnchor;
  bool _restoreChoiceFocus = false;
  bool? _chooserTraversal;
  bool _focusScheduled = false;
  final _fieldsScroll = ScrollController();
  final _choicesScroll = ScrollController();
  _Row _row = _Row.start;
  final _itemKeys = {for (final row in _Row.values) row: GlobalKey()};
  final _choiceKey = GlobalKey();
  final _searchKey = GlobalKey();

  static const _advancedRows = {
    _Row.model,
    _Row.approvals,
    _Row.profile,
    _Row.branch,
    _Row.worktree,
  };

  List<_Row> get _rows => [
    for (final row in _Row.values)
      if ((!_advancedRows.contains(row) || box.advancedOpen) &&
          (row != _Row.profile || box.usesProfile) &&
          (row != _Row.model || !box.isTerminal) &&
          (row != _Row.approvals || box.hasModes))
        row,
  ];

  /// Choices can be visible before they own keyboard focus.
  bool _listOpen = false;
  bool _hideChoices = false;
  String? _folderAction;

  @override
  void initState() {
    super.initState();
    _observedField = box.field;
    box.addListener(_onBox);
    widget.devicePort?.attach(_deviceSnapshot, _deviceAction);
    // The pane colours can change under an open dialog; it wears them too.
    terminalThemeStore.addListener(_onBox);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (box.checking) _row = _Row.start;
      _syncField();
      (widget.desktop ? _desktopDefaultFocus : _focus).requestFocus();
    });
  }

  @override
  void dispose() {
    widget.devicePort?.detach();
    box.removeListener(_onBox);
    terminalThemeStore.removeListener(_onBox);
    _inputFocus.dispose();
    _queryText.dispose();
    _taskText.dispose();
    _taskFocus.dispose();
    _taskToggleFocus.dispose();
    _dialogScope.dispose();
    _machineFocus.dispose();
    for (final node in _desktopFocus.values) {
      node.dispose();
    }
    _fieldsScroll.dispose();
    _choicesScroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  NewHarnessField? _observedField;
  void _onBox() {
    if (!mounted) return;
    // Explicit tasks and restored drafts are never hidden behind Add task.
    if (box.task.isNotEmpty) _taskExpanded = true;
    if (_taskText.text != box.task) {
      _taskText.value = TextEditingValue(
        text: box.task,
        selection: TextSelection.collapsed(offset: box.task.length),
      );
    }
    if (_queryText.text != box.query) {
      _queryText.value = TextEditingValue(
        text: box.query,
        selection: TextSelection.collapsed(offset: box.query.length),
      );
    }
    if (_observedField != box.field) {
      _observedField = box.field;
      final next = switch (box.field) {
        NewHarnessField.harness => _Row.agent,
        NewHarnessField.agent => _Row.agent,
        NewHarnessField.model => _Row.model,
        NewHarnessField.machine => _Row.project,
        NewHarnessField.branch => _Row.branch,
        NewHarnessField.mode => _Row.approvals,
        NewHarnessField.profile => _Row.profile,
        NewHarnessField.projectMenu ||
        NewHarnessField.project ||
        NewHarnessField.projectName ||
        NewHarnessField.projectRepository => _Row.project,
        NewHarnessField.launch => _Row.start,
        _ => _row,
      };
      final hidden = widget.desktop
          ? {_Row.model, _Row.profile, _Row.branch}.contains(next)
          : _advancedRows.contains(next);
      if (hidden && !box.advancedOpen) {
        box.toggleAdvanced();
      }
      if (next != _row) {
        _row = next;
        _listOpen = false;
        _takeWheel();
      }
    }
    if (_row == _Row.model && !_picking) _takeWheel();
    setState(() {});
    // A required choice or a pending launch disables Start. Keep Escape and
    // keyboard recovery inside the dialog while its button rebuilds.
    if (widget.desktop &&
        _desktopFocus[_Row.start]!.hasFocus &&
        !_desktopStartEnabled) {
      _focusEditor();
    }
    _revealRow();
  }

  void _focusEditor() {
    if (_focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted) return;
      if (_picking) {
        _inputFocus.requestFocus();
      } else if (widget.desktop) {
        final origin = _chooserOrigin;
        if (_restoreChoiceFocus &&
            origin?.context != null &&
            origin!.canRequestFocus) {
          origin.requestFocus();
          if (_chooserTraversal case final forward?) {
            forward ? origin.nextFocus() : origin.previousFocus();
          }
        } else {
          _desktopDefaultFocus.requestFocus();
        }
        _restoreChoiceFocus = false;
        _chooserTraversal = null;
      } else {
        _focus.requestFocus();
      }
    });
  }

  void dismissFromOutside() {
    if (widget.desktop && _picking && !box.locked) {
      _closeDesktopChooser();
    } else {
      _runCommand(_cancel);
    }
  }

  void _closeDesktopChooser({bool? next}) {
    _folderAction = null;
    box.setQuery('');
    box.focusField(NewHarnessField.launch);
    setState(() {
      _row = _Row.start;
      _listOpen = false;
      _hideChoices = true;
    });
    _restoreChoiceFocus = true;
    _chooserTraversal = next;
    _focusEditor();
  }

  /// The field a row edits, or null where the row is its own answer.
  static const _projectFields = {
    NewHarnessField.projectMenu,
    NewHarnessField.project,
    NewHarnessField.projectName,
    NewHarnessField.projectRepository,
  };

  NewHarnessField? _fieldOf(_Row row) => switch (row) {
    _Row.project =>
      (_projectFields.contains(box.field) ||
              box.field == NewHarnessField.machine)
          ? box.field
          : NewHarnessField.projectMenu,
    _Row.agent =>
      box.field == NewHarnessField.agent
          ? NewHarnessField.agent
          : NewHarnessField.harness,
    _Row.model => NewHarnessField.model,
    _Row.branch => NewHarnessField.branch,
    _Row.worktree => null,
    _Row.approvals => NewHarnessField.mode,
    _Row.profile => NewHarnessField.profile,
    _Row.advanced || _Row.start => null,
  };

  /// Why a row cannot be changed, in the words the row will wear.
  String? _blocked(_Row row) => switch (row) {
    _Row.branch || _Row.worktree when box.checkingGit => '',
    _Row.branch when box.gitError != null => box.gitError,
    _Row.branch when !box.isGitProject => 'Not a Git repository',
    _Row.worktree when box.gitError != null => box.gitError,
    _Row.worktree when !box.canUseWorktree => 'Not a Git repository',
    _ => null,
  };

  String _label(_Row row) => switch (row) {
    _Row.advanced => 'Options',
    _Row.project => 'Project',
    _Row.agent => 'Agent',
    _Row.model => 'Model',
    _Row.branch => 'Branch',
    _Row.worktree => 'Worktree',
    _Row.approvals => 'Approvals',
    _Row.profile => 'Profile',
    _Row.start => 'New Harness',
  };

  /// What the row currently answers — or, while its list is open, what the
  /// highlight would make it, so the row never disagrees with the list.
  String _value(_Row row) => _valueOf(row);

  String _valueOf(_Row row) => switch (row) {
    _Row.advanced => box.advancedOpen ? '[-]' : '[+]',
    _Row.project => box.launchProjectLabel,
    _Row.agent => box.launchAgentLabel,
    _Row.model => box.modelLabel,
    _Row.branch => box.branchRowLabel,
    _Row.worktree => box.worktree ? '[x]' : '[ ]',
    _Row.approvals => box.modeLabel,
    _Row.profile => box.profileLabel ?? 'Default',
    _Row.start => box.checking ? 'Check status' : _label(row),
  };

  // These leave this form for a native sheet, account flow or another route.
  // Until those surfaces have a semantic remote, keep them explicit on desktop.
  static const _desktopDoors = {
    NewHarnessController.browseId,
    NewHarnessController.linkProfileId,
    NewHarnessController.storeId,
    NewHarnessController.manageModelsId,
  };

  // Names in existing lists, never a shell command, folder path or repository
  // URL. Speaking filters; choosing and creating remain distinct gestures.
  static const _voiceSearchFields = {
    NewHarnessField.harness,
    NewHarnessField.agent,
    NewHarnessField.projectMenu,
    NewHarnessField.machine,
    NewHarnessField.model,
    NewHarnessField.branch,
    NewHarnessField.profile,
    NewHarnessField.mode,
  };

  Map<String, dynamic> _deviceSnapshot() {
    final option = _picking ? box.selected : null;
    final rows = _rows;
    final index = _picking ? box.cursor : rows.indexOf(_row);
    final count = _picking ? box.options.length : rows.length;
    String at(int i) => i < 0 || i >= count
        ? ''
        : _picking
        ? box.options[i].title
        : _label(rows[i]);
    final blocked = _blocked(_row);
    final desktop = option != null && _desktopDoors.contains(option.id);
    return {
      'active': true,
      'title': _picking ? _label(_row) : 'New Harness',
      'label': _picking ? option?.title ?? 'No matches' : _label(_row),
      'detail': _picking
          ? option?.detail ?? ''
          : _row == _Row.start
          ? '${box.launchAgentLabel}\n${box.launchProjectLabel}'
          : _value(_row),
      'previous': at(index - 1),
      'next': at(index + 1),
      'position': index < 0 ? 0 : index + 1,
      'total': count,
      'busy': box.busy || box.linkingProfile,
      'canQuery':
          !box.locked &&
          !_isComposing() &&
          _fieldOf(_row) != null &&
          blocked == null &&
          _voiceSearchFields.contains(box.field),
      'query': box.query,
      'enabled':
          !box.busy &&
          !box.linkingProfile &&
          blocked == null &&
          !desktop &&
          (!_picking || option?.enabled == true),
      'action': _picking
          ? 'choose'
          : _row == _Row.start
          ? box.checking
                ? 'check status'
                : 'start'
          : _row == _Row.worktree || _row == _Row.advanced
          ? 'toggle'
          : 'open',
      'error':
          box.error ??
          (desktop
              ? 'Continue on desktop for this choice.'
              : blocked ?? (option?.enabled == false ? option?.why : null)) ??
          '',
      'status': box.status ?? '',
      // Full identities and launch settings stay in the revision guard. A
      // short device label cannot authorize a different same-named project.
      'guard': jsonEncode([
        box.field.name,
        option?.id,
        option?.machineId,
        option?.project?.folder,
        option?.project?.repository?.url,
        option?.project?.name,
        box.machineId,
        box.engine,
        box.harnessId,
        box.project.folder,
        box.project.repository?.url,
        box.project.name,
        box.mode,
        box.model?.id,
        box.model?.grid,
        box.model?.node,
        box.draft.profile?.path,
        box.branchRef,
        box.branchRowLabel,
        box.worktree,
        box.task,
      ]),
    };
  }

  void _deviceAction(String op, int delta, String? text) {
    if (!mounted || _isComposing()) return;
    if (op == 'back') {
      _cancel();
    } else if (op == 'close') {
      if (box.requestDismiss()) widget.onClose();
    } else if (op == 'move') {
      if (!box.locked) _picking ? _stepMatch(delta) : _moveRow(delta);
    } else if (op == 'activate') {
      if (_deviceSnapshot()['enabled'] == true) _confirm();
    } else if (op == 'query' &&
        _deviceSnapshot()['canQuery'] == true &&
        text != null) {
      // A recognizer often adds a final period to a spoken name. Preserve the
      // name, Unicode and internal punctuation; never interpret it as a command.
      final query = text
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim()
          .replaceFirst(RegExp(r'[.!?。！？]+$'), '')
          .trim();
      if (query.isNotEmpty) _onTyped(query);
    }
    if (mounted) {
      _focusEditor();
      _revealRow();
    }
  }

  /// Focusing a row focuses the field it edits, so the controller's option
  /// list — and therefore ← and → — is already the right one.
  void _syncField() {
    final field = _fieldOf(_row);
    if (field == null) {
      _wheel = const [];
      if (_row == _Row.start) box.focusField(NewHarnessField.launch);
      return;
    }
    box.focusField(field);
    _takeWheel();
  }

  void _moveRow(int delta) {
    if (box.busy || box.linkingProfile) return;
    final rows = _rows;
    setState(() {
      _row = rows[(rows.indexOf(_row) + delta) % rows.length];
      _listOpen = false;
      _hideChoices = false;
    });
    if (box.query.isNotEmpty) box.setQuery('');
    _syncField();
    _revealRow();
  }

  void _revealRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_picking &&
          _choicesScroll.hasClients &&
          box.cursor >= 0 &&
          box.cursor < box.options.length) {
        final top = widget.desktop
            ? 6 +
                  List.generate(
                    box.cursor,
                    _desktopChoiceHeight,
                  ).fold<double>(0, (a, b) => a + b)
            : List.generate(
                    box.cursor,
                    _choiceLines,
                  ).fold<int>(0, (a, b) => a + b) *
                  _rowHeight;
        final bottom =
            top +
            (widget.desktop
                ? _desktopChoiceHeight(box.cursor)
                : _choiceLines(box.cursor) * _rowHeight);
        final position = _choicesScroll.position;
        if (top < position.pixels ||
            bottom > position.pixels + position.viewportDimension) {
          _choicesScroll.jumpTo(
            (top < position.pixels ? top : bottom - position.viewportDimension)
                .clamp(0, position.maxScrollExtent),
          );
        }
        return;
      }
      final context = _picking
          ? _choiceKey.currentContext
          : _itemKeys[_row]?.currentContext;
      if (context == null) return;
      final target = context.findRenderObject();
      final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (target is! RenderBox ||
          viewport is! RenderBox ||
          !target.hasSize ||
          !viewport.hasSize) {
        return;
      }
      final top = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top < 0 || top + target.size.height > viewport.size.height) {
        Scrollable.ensureVisible(context, alignment: top < 0 ? 0 : 1);
      }
    });
  }

  /// ← and → on a row that is its own answer flip it; everywhere else they
  /// step the field's options and apply the new one where it stands.
  /// The values this row steps through, captured when the row is focused.
  /// The controller's displayed list re-ranks the chosen row to the front,
  /// so stepping through THAT walks in circles; a wheel taken once does not
  /// move under the arrows.
  List<NewHarnessOption> _wheel = const [];
  int _at = 0;

  void _takeWheel() {
    _wheel = box.stepValues();
    _at = _wheel.indexWhere(box.isCurrent);
    if (_at < 0) _at = 0;
  }

  void _stepValue(int delta) {
    if (box.locked || _blocked(_row) != null) return;
    if (_row == _Row.advanced) {
      _toggleAdvanced();
      return;
    }
    if (_row == _Row.worktree) {
      setState(box.toggleWorktree);
      return;
    }
    if (_wheel.isEmpty) _takeWheel();
    if (_wheel.isEmpty) return;
    // Follow the value if something else moved it, then step from there.
    final now = _wheel.indexWhere(box.isCurrent);
    if (now >= 0) _at = now;
    _at = (_at + delta) % _wheel.length;
    box.applyOption(_wheel[_at]);
  }

  /// Close the chooser and hand the keys back to the rows.
  ///
  /// Left returns from a chooser, including in a narrow window.
  void _backToRows() {
    if (_prompts.contains(box.field) ||
        (box.field == NewHarnessField.machine && _folderAction != null)) {
      box.focusField(NewHarnessField.projectMenu);
    } else if (box.field == NewHarnessField.agent) {
      box.focusField(NewHarnessField.harness);
    }
    _folderAction = null;
    box.setQuery('');
    setState(() {
      _listOpen = false;
      _hideChoices = true;
    });
    _focus.requestFocus();
    _revealRow();
  }

  void _switchPane({bool reverse = false}) {
    if (box.locked) return;
    if (widget.desktop && _picking) {
      _closeDesktopChooser(next: !reverse);
      return;
    }
    if (_picking) {
      _backToRows();
    } else if (_hasChoices) {
      setState(() => _listOpen = true);
    }
  }

  /// Folder paths, project names and repository URLs keep their prompt active
  /// even before anything is typed.
  static const _prompts = {
    NewHarnessField.project,
    NewHarnessField.projectName,
    NewHarnessField.projectRepository,
  };

  bool get _picking =>
      (_listOpen || box.query.isNotEmpty || _prompts.contains(box.field)) &&
      _fieldOf(_row) != null &&
      _blocked(_row) == null;

  bool _isComposing() =>
      (_queryText.value.composing.isValid &&
          !_queryText.value.composing.isCollapsed) ||
      (_taskFocus.hasFocus &&
          _taskText.value.composing.isValid &&
          !_taskText.value.composing.isCollapsed);

  /// Typing filters the focused field's choices; Return commits the selection.
  void _onTyped(String value) {
    if (box.locked || _fieldOf(_row) == null || _blocked(_row) != null) return;
    setState(() => _listOpen = true);
    box.setQuery(value);
    _focusEditor();
  }

  void _insertText(String text) {
    if (box.locked || _fieldOf(_row) == null || _blocked(_row) != null) return;
    final value = _queryText.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final next = value.text.replaceRange(selection.start, selection.end, text);
    _queryText.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    _onTyped(next);
  }

  Future<void> _pasteQuery() async {
    if (box.locked || _fieldOf(_row) == null || _blocked(_row) != null) return;
    final row = _row;
    final field = box.field;
    final query = box.query;
    final selection = _queryText.selection;
    bool stillEditing() =>
        mounted &&
        !box.locked &&
        _row == row &&
        box.field == field &&
        box.query == query &&
        _queryText.selection == selection;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!stillEditing() || data?.text?.isNotEmpty != true) return;
      _insertText(data!.text!.replaceAll(RegExp(r'[\r\n]+'), ' '));
      _revealRow();
    } on PlatformException {
      if (stillEditing()) box.warn('Could not paste. Try again.');
    }
  }

  /// Walk the choices without changing the field's saved value.
  void _stepMatch(int delta) {
    // Move the highlight and nothing else. Taking each row as it is passed
    // applies a project, which reselects its machine, which refreshes the
    // list with a reset cursor — the highlight snapped home on every press.
    // The doors ARE drawn, so the arrows land on them: a row you can see and
    // cannot reach is worse than one that is not there.
    setState(() => box.move(delta));
  }

  void _pageMatches(int direction) {
    final height = _choicesScroll.hasClients
        ? _choicesScroll.position.viewportDimension
        : _rowHeight;
    var covered = 0.0;
    var count = 0;
    for (
      var i = box.cursor + direction;
      i >= 0 && i < box.options.length && covered < height;
      i += direction
    ) {
      covered += widget.desktop
          ? _desktopChoiceHeight(i)
          : _choiceLines(i) * _rowHeight;
      count++;
    }
    box.page(direction, count);
  }

  /// The rows that open something instead of answering the row. Being
  /// synthetic is not enough to qualify — "Create branch x" is synthetic and
  /// is an answer — so they are named.
  static const _doors = {
    NewHarnessController.browseId,
    NewHarnessController.newProjectId,
    NewHarnessController.repositoryId,
    NewHarnessController.existingProjectId,
    NewHarnessController.changeMachineId,
    NewHarnessController.linkProfileId,
    NewHarnessController.refreshProfilesId,
    NewHarnessController.storeId,
    NewHarnessController.manageModelsId,
    NewHarnessController.refreshModelsId,
  };
  bool _isDoor(NewHarnessOption option) => _doors.contains(option.id);

  /// Clone, Open Folder and New Project are doors rather than values: they
  /// open a prompt or the system chooser instead of answering the row.
  void _openDoor(NewHarnessOption option) {
    if (box.locked || !option.enabled) return;
    if (option.id == NewHarnessController.changeMachineId) {
      // focusField(machine) remembers the prompt and its uncommitted query.
      // Clearing first loses a typed name/path when Escape comes back here.
      _chooseFolderMachine(switch (box.field) {
        NewHarnessField.projectName => NewHarnessController.newProjectId,
        NewHarnessField.projectRepository => NewHarnessController.repositoryId,
        _ => NewHarnessController.existingProjectId,
      }, preferLocal: false);
      return;
    }
    box.setQuery('');
    if (option.id == NewHarnessController.manageModelsId) {
      unawaited(box.app.runLocalModel(context));
      return;
    }
    if (option.id == NewHarnessController.refreshModelsId) {
      unawaited(box.refreshModels());
      return;
    }
    if (option.id == NewHarnessController.storeId) {
      widget.onStore?.call();
      return;
    }
    if (option.id == NewHarnessController.linkProfileId) {
      widget.onLinkProfile?.call();
      return;
    }
    if (option.id == NewHarnessController.refreshProfilesId) {
      unawaited(box.refreshProfiles());
      return;
    }
    if (option.id == NewHarnessController.browseId) {
      unawaited(_browse());
      return;
    }
    _chooseFolderMachine(option.id);
  }

  void _chooseFolderMachine(String action, {bool preferLocal = true}) {
    _folderAction = action;
    if (widget.desktop && preferLocal) {
      // Machine is already the first explicit configuration choice. Continue
      // on that machine; Change machine remains available in the path chooser.
      box.focusField(switch (action) {
        NewHarnessController.newProjectId => NewHarnessField.projectName,
        NewHarnessController.repositoryId => NewHarnessField.projectRepository,
        _ => NewHarnessField.project,
      });
      setState(() => _listOpen = true);
      return;
    }
    box.focusField(NewHarnessField.machine);
    if (preferLocal) {
      final local = box.options.indexWhere(
        (option) => box.app.stateOf(option.id)?.isLocalMachine == true,
      );
      if (local >= 0) box.cursor = local;
    }
    setState(() => _listOpen = true);
  }

  Future<void> _browse() async {
    final machineId = box.machineId;
    try {
      await widget.onBrowse?.call();
    } on Exception {
      if (mounted &&
          box.machineId == machineId &&
          box.field == NewHarnessField.project) {
        box.warn('Could not browse folders. Try again.');
      }
    }
    if (!mounted) return;
    if (box.field == NewHarnessField.launch) _selectRow(_Row.project);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusEditor();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _checkingLaunch = false;

  Future<void> _start() async {
    if (box.busy) return;
    _restoreChoiceFocus = false;
    if (box.requiredChoice case final choice?) {
      box.focusField(choice.field);
      setState(() => _listOpen = true);
      box.warn(choice.message);
      _focusEditor();
      _revealRow();
      return;
    }
    _checkingLaunch = box.checking;
    final outcome = await box.create();
    if (!mounted) return;
    switch (outcome) {
      case NewHarnessOutcome.created:
        widget.onCreated();
      case NewHarnessOutcome.failed:
        // The controller has said why on the line; keep the keys live.
        if (box.requiredChoice != null) {
          setState(() => _listOpen = true);
          _focusEditor();
          _revealRow();
        } else {
          _focusEditor();
        }
    }
  }

  void _acceptChoice(NewHarnessOption option) {
    if (box.locked) return;
    if (!option.enabled) {
      box.accept(option);
      return;
    }
    if (_isDoor(option)) {
      _openDoor(option);
    } else {
      final field = box.field;
      if (widget.desktop &&
          field == NewHarnessField.machine &&
          _folderAction != null) {
        // The controller owns the originating prompt: names and repository
        // URLs travel to another machine; paths only survive on the same one.
        box.accept(option);
        _focusEditor();
        _revealRow();
        return;
      }
      final prompt = _prompts.contains(box.field);
      box.applyOption(option);
      final taskWarning =
          (field == NewHarnessField.harness ||
                  field == NewHarnessField.agent) &&
              box.isTerminal &&
              box.engine == option.id &&
              box.compatibleEngines.contains(option.id) &&
              box.task.trim().isNotEmpty
          ? box.error
          : null;
      if (box.error != null && taskWarning == null) return;
      box.setQuery('');
      if (field == NewHarnessField.machine && _folderAction != null) {
        box.focusField(switch (_folderAction) {
          NewHarnessController.newProjectId => NewHarnessField.projectName,
          NewHarnessController.repositoryId =>
            NewHarnessField.projectRepository,
          _ => NewHarnessField.project,
        });
        setState(() => _listOpen = true);
      } else if (field == NewHarnessField.harness && box.harnessId != null) {
        box.focusField(NewHarnessField.agent);
        setState(() => _listOpen = true);
      } else {
        if (prompt) box.focusField(NewHarnessField.projectMenu);
        if (field == NewHarnessField.agent) {
          box.focusField(NewHarnessField.harness);
        }
        _folderAction = null;
        if (widget.desktop) {
          _closeDesktopChooser();
        } else {
          _selectRow(_Row.start);
        }
      }
      // Terminal was selected successfully. Keep the draft warning visible
      // after returning to the composer, where Start still asks for consent.
      if (taskWarning != null) box.warn(taskWarning);
    }
    _focusEditor();
    _revealRow();
  }

  void _confirm() {
    // Return chooses a value in the list; only the start row launches.
    if (_picking) {
      final option = box.selected;
      if (option != null) {
        _acceptChoice(option);
      } else if (_prompts.contains(box.field)) {
        box.accept();
      } else {
        box.warn('No values match this search.');
      }
    } else if (_row == _Row.advanced) {
      _toggleAdvanced();
    } else if (_row == _Row.worktree && _blocked(_row) == null) {
      setState(box.toggleWorktree);
    } else if (_row != _Row.start) {
      // Return opens the row's choices. It never starts an agent from a
      // value row — only the button does that.
      if (_blocked(_row) == null) setState(() => _listOpen = true);
    } else {
      unawaited(_start());
    }
  }

  void _cancel() {
    if (box.locked) {
      if (box.requestDismiss()) widget.onClose();
      return;
    }
    // Escape goes back one screen, discarding its uncommitted search.
    if (box.field == NewHarnessField.agent && _picking) {
      box.focusField(NewHarnessField.harness);
      setState(() => _listOpen = true);
    } else if (widget.desktop &&
        box.field == NewHarnessField.machine &&
        _folderAction != null) {
      box.back();
      setState(() => _listOpen = true);
    } else if (_prompts.contains(box.field) && _folderAction != null) {
      if (widget.desktop) {
        _folderAction = null;
        box.focusField(NewHarnessField.projectMenu);
        setState(() => _listOpen = true);
      } else {
        _chooseFolderMachine(_folderAction!, preferLocal: false);
      }
    } else if (_prompts.contains(box.field) ||
        (box.field == NewHarnessField.machine && _folderAction != null)) {
      _folderAction = null;
      setState(() {
        box.focusField(NewHarnessField.projectMenu);
        _listOpen = true;
      });
    } else if (widget.desktop && _picking) {
      _closeDesktopChooser();
    } else if (_picking || (!_hideChoices && _hasChoices)) {
      setState(() {
        _listOpen = false;
        _hideChoices = true;
      });
      box.setQuery('');
    } else {
      if (box.requestDismiss()) widget.onClose();
    }
  }

  void _runCommand(VoidCallback action) {
    if (_isComposing()) return;
    action();
    _focusEditor();
    _revealRow();
  }

  void _runCreationCommand(VoidCallback action) {
    if (box.locked) return;
    _runCommand(action);
  }

  void _openCreationRow(_Row row) {
    _folderAction = null;
    // A direct shortcut enters the top-level chooser, even when another
    // chooser currently owns a nested project or specialized-agent prompt.
    box.focusField(
      row == _Row.project
          ? NewHarnessField.projectMenu
          : NewHarnessField.harness,
    );
    _activateRow(row);
  }

  void _openMachineChooser() {
    if (box.locked) return;
    _folderAction = null;
    _chooserOrigin = _machineFocus;
    _chooserAnchor = _machineAnchor;
    _restoreChoiceFocus = false;
    _selectRow(_Row.project);
    box.focusField(NewHarnessField.machine);
    setState(() => _listOpen = true);
    _focusEditor();
  }

  void _creationMachine() {
    if (_picking && _prompts.contains(box.field)) {
      _openDoor(
        const NewHarnessOption(
          id: NewHarnessController.changeMachineId,
          title: 'Change Machine',
          synthetic: true,
        ),
      );
    } else {
      _openMachineChooser();
    }
  }

  void _creationProject(String action) {
    _openCreationRow(_Row.project);
    final option = box.options.where((item) => item.id == action).firstOrNull;
    if (option != null) _openDoor(option);
  }

  void _creationBrowse() {
    if (box.field != NewHarnessField.project) {
      _creationProject(NewHarnessController.existingProjectId);
    }
    _openDoor(
      const NewHarnessOption(
        id: NewHarnessController.browseId,
        title: 'Browse Folder',
        synthetic: true,
      ),
    );
  }

  void _creationTask() {
    if (_picking) _closeDesktopChooser();
    setState(() => _taskExpanded = true);
    _restoreChoiceFocus = false;
    _chooserTraversal = null;
    _focusEditor();
  }

  List<NewHarnessOption> get _recentProjectChoices => box.options
      .where((option) => !option.synthetic && option.project?.folder != null)
      .toList();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.handled;
    }
    if (widget.desktop && !_picking) {
      if (_isComposing()) return KeyEventResult.skipRemainingHandlers;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (event is KeyDownEvent) _cancel();
        return KeyEventResult.handled;
      }
      if (KeymapTheme.of(context) == null &&
          HardwareKeyboard.instance.isMetaPressed &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        if (event is KeyDownEvent) unawaited(_start());
        return KeyEventResult.handled;
      }
      if (_focus.hasPrimaryFocus &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
        if (event is KeyDownEvent) unawaited(_start());
        return KeyEventResult.handled;
      }
      // The multiline editor and native button focus own ordinary editing,
      // Enter, and Tab. Typing must never become a configuration search.
      return KeyEventResult.ignored;
    }
    // Candidate navigation and confirmation belong to the input method. Keep
    // these keys out of both the picker and ancestor focus-traversal shortcuts.
    if (_isComposing()) return KeyEventResult.skipRemainingHandlers;
    if (event.logicalKey == LogicalKeyboardKey.keyR &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        box.canRefreshChoices) {
      if (event is KeyDownEvent) box.refreshChoices();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      if (event is KeyDownEvent) unawaited(_pasteQuery());
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.tab:
        // Arrows move within a pane; Tab switches panes without choosing.
        _switchPane();
      case LogicalKeyboardKey.arrowDown:
        // While the list is open it owns ↑↓, so the rows below do not move
        // under a highlight the reader is using to choose.
        _picking ? _stepMatch(1) : _moveRow(1);
      case LogicalKeyboardKey.arrowUp:
        _picking ? _stepMatch(-1) : _moveRow(-1);
      case LogicalKeyboardKey.arrowRight:
        // → goes to the COLUMN on the right, it does not edit the value on
        // the left. Two columns side by side, and the arrow follows the eye:
        // reading the choices and reaching for → to get at them is what
        // everybody tried first. A row with no column to enter — Worktree,
        // which is two values and nothing to browse — still flips in place.
        if (_picking) return KeyEventResult.ignored; // the caret's key now
        if (_hasChoices) {
          setState(() => _listOpen = true);
        } else {
          _stepValue(1);
        }
      case LogicalKeyboardKey.arrowLeft:
        if (_picking) {
          // With something typed, ← is an editing key: it moves through the
          // characters rather than walking out of the search they are in.
          if (box.query.isNotEmpty) return KeyEventResult.ignored;
          _backToRows();
        } else if (!_hasChoices) {
          _stepValue(-1);
        }
      case LogicalKeyboardKey.pageDown:
        // The wheel's home now that the arrows have left it — as documented
        // long before this: hyphens are values, so - and + cannot serve.
        if (!_picking) {
          _stepValue(1);
        } else {
          _pageMatches(1);
        }
      case LogicalKeyboardKey.pageUp:
        if (!_picking) {
          _stepValue(-1);
        } else {
          _pageMatches(-1);
        }
      case LogicalKeyboardKey.space:
        if (_picking || _row != _Row.worktree) return KeyEventResult.ignored;
        _stepValue(1);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.handled;
        }
        _confirm();
      case LogicalKeyboardKey.escape:
        _cancel();
      case LogicalKeyboardKey.backspace:
        if (_inputFocus.hasFocus) return KeyEventResult.ignored;
        final query = box.query;
        if (query.isEmpty) return KeyEventResult.ignored;
        final selection = _queryText.selection;
        if (!selection.isValid) return KeyEventResult.ignored;
        if (selection.isCollapsed && selection.start > 0) {
          final before = query.substring(0, selection.start);
          _queryText.selection = TextSelection(
            baseOffset: before.characters.skipLast(1).toString().length,
            extentOffset: selection.end,
          );
        }
        _insertText('');
      default:
        // A real text client owns native paste, selection, and composition.
        // Only the first printable key on an idle field needs forwarding.
        if (_inputFocus.hasFocus) return KeyEventResult.ignored;
        // Typing narrows the highlighted item. There is no separate input to
        // move to — the item is the input, which is what keeps this one
        // screen. `-` and `+` are values, so they never reach here.
        final typed = event.character;
        if (typed == null || typed.isEmpty || typed.codeUnitAt(0) < 0x20) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          return KeyEventResult.ignored;
        }
        _insertText(typed);
    }
    _focusEditor();
    _revealRow();
    return KeyEventResult.handled;
  }

  TerminalTheme get _theme =>
      terminalThemeFor(grid.AppTheme.palette.value, terminalThemeStore.value);

  Color get _faint => widget.desktop
      ? DesktopChrome.muted
      : _theme.foreground.withValues(alpha: .54);

  // Only the column that owns the keys carries Open Harness's full highlight.
  Color get _activeFill => _theme.selection;

  /// A machine that cannot be picked — unlinked or offline — in dark grey,
  /// darker than the faint of an idle list, so it recedes rather than warns.
  Color get _unavailableInk => _theme.foreground.withValues(alpha: .28);

  Color get _idleFill => _theme.foreground.withValues(alpha: .04);

  /// One face, one size, everywhere on this screen — and it is the
  /// TERMINAL's size, the one ⌘+ and ⌘− set, not the UI's fixed 13pt. A box
  /// that stays small beside a zoomed terminal reads as another application.
  ///
  /// Its line height IS the row, so every line of every text on this form —
  /// wrapped ones included — lands on the grid by itself. A two-line notice
  /// is exactly two rows; nothing needs a box around it to stay in step.
  TextStyle _ink([Color? color]) => widget.desktop
      ? DesktopChrome.text(
          color: color == _theme.foreground ? DesktopChrome.foreground : color,
        )
      : terminalContentStyle(color: color ?? _theme.foreground);

  /// THE GRID. A terminal has two units and positions nothing in pixels:
  ///
  /// * [_cell] — one character wide, in the terminal's own face and size.
  /// * [_rowHeight] — one row tall; a field, a name, a description line and
  ///   the gap between entries are each exactly one.
  ///
  /// Every margin, column and gap on this form is a whole number of one of
  /// them. Per-widget pixel padding is what gave each pane three left edges
  /// and let the two columns drift apart; a grid cannot drift.
  ///
  /// Both are measured through the text scaler, because that is what the
  /// glyphs are drawn at.
  double _cell = 8;
  double _rowHeight = 20;

  void _measureGrid(BuildContext context) {
    if (widget.desktop) {
      _cell = 8;
      _rowHeight = (MediaQuery.textScalerOf(context).scale(14) * 1.45 + 12);
      return;
    }
    final cell = terminalCellSizeOf(context);
    _cell = cell.width;
    _rowHeight = cell.height;
  }

  /// Where each pane's rows sit: one cell in from the pane's edge, so the
  /// selection bar has a column of air on either side.
  double get _margin => _cell;

  /// The fzf pointer column in the choices: `>`, and the action glyphs, live
  /// in these two cells, and every name, heading and notice starts after it.
  double get _gutter => _cell * 2;

  /// The longest label is Approvals (nine cells), followed by two spaces.
  /// Every editable field uses this same value column.
  static const _labelCells = 9;
  static const _labelGapCells = 2;

  /// One row, with its content sitting on the line.
  Widget _oneRow(Widget child) => SizedBox(
    height: _rowHeight,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  /// Geometry follows the same size, so the columns keep their proportions.
  double _scale = 1;

  /// Notices need real rows too; otherwise a compact frame clips the reason
  /// a launch was refused below its last action.
  int _noticeRows(BuildContext context, int columns) {
    if (_picking) return 0;
    final required = box.requiredChoice?.message;
    final messages = [
      ?required,
      if ((box.error != null || box.status != null) &&
          (box.error == null || box.error != required))
        box.error ?? box.status!,
    ];
    var rows = 0;
    for (final message in messages) {
      rows += 1 + _textRows(context, message, columns - 4);
    }
    return rows;
  }

  int _textRows(BuildContext context, String text, int columns) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _ink()),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: columns.clamp(1, 1000) * _cell);
    final rows = (painter.height / _rowHeight).ceil();
    painter.dispose();
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    TerminalFontScope.watch(context);
    final scale = terminalTextScaleOf(context);
    if (_scale != scale) {
      _scale = scale;
      _revealRow();
    }
    _measureGrid(context);
    final recentProjects =
        widget.desktop && box.field == NewHarnessField.projectMenu
        ? _recentProjectChoices
        : const <NewHarnessOption>[];
    final form = KeymapRegion(
      contextKind:
          widget.desktop &&
              _picking &&
              (_projectFields.contains(box.field) ||
                  box.field == NewHarnessField.machine && _folderAction != null)
          ? KeymapContext.project
          : KeymapContext.picker,
      composing: _isComposing,
      actions: {
        if (widget.desktop) ...{
          'creation.agent': () =>
              _runCreationCommand(() => _openCreationRow(_Row.agent)),
          'creation.project': () =>
              _runCreationCommand(() => _openCreationRow(_Row.project)),
          'creation.project_machine': () =>
              _runCreationCommand(_creationMachine),
          'creation.task': () => _runCreationCommand(_creationTask),
          'creation.options': () =>
              _runCreationCommand(() => _activateRow(_Row.advanced)),
          'creation.project_new': () => _runCreationCommand(
            () => _creationProject(NewHarnessController.newProjectId),
          ),
          'creation.project_existing': () => _runCreationCommand(
            () => _creationProject(NewHarnessController.existingProjectId),
          ),
          'creation.project_repository': () => _runCreationCommand(
            () => _creationProject(NewHarnessController.repositoryId),
          ),
          if (widget.onBrowse != null)
            'creation.project_browse': () =>
                _runCreationCommand(_creationBrowse),
          if (box.field == NewHarnessField.projectMenu)
            for (
              var index = 0;
              index < recentProjects.length && index < 9;
              index++
            )
              'creation.project_recent_${index + 1}': () =>
                  _runCreationCommand(() {
                    final choices = _recentProjectChoices;
                    if (index < choices.length) _acceptChoice(choices[index]);
                  }),
        },
        if (widget.desktop)
          'picker.add_here': () {
            if (!_isComposing() && !_picking) unawaited(_start());
          },
        if (!widget.desktop || _picking) ...{
          'picker.accept': () => _runCommand(_confirm),
          'picker.next': () =>
              _runCommand(() => _picking ? _stepMatch(1) : _moveRow(1)),
          'picker.previous': () =>
              _runCommand(() => _picking ? _stepMatch(-1) : _moveRow(-1)),
          'picker.complete': () => _runCommand(_switchPane),
          'picker.complete_back': () =>
              _runCommand(() => _switchPane(reverse: true)),
        },
        'picker.cancel': () => _runCommand(_cancel),
        'picker.more_options': () {
          if (!box.locked) _toggleAdvanced();
        },
      },
      child: Focus(
        key: const ValueKey('new-harness-form'),
        focusNode: _focus,
        skipTraversal: widget.desktop,
        onKeyEvent: _onKey,
        child: widget.desktop
            ? Material(
                type: MaterialType.transparency,
                child: _desktopComposer(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / _cell).floor();
                  final rows = (constraints.maxHeight / _rowHeight).floor();
                  final mainColumns = columns.clamp(1, 56);
                  final contentRows =
                      _rows.length +
                      5 +
                      (box.task.isNotEmpty ? 1 : 0) +
                      _noticeRows(context, mainColumns);
                  final mainRows = rows.clamp(1, contentRows);
                  final left = (columns - mainColumns) ~/ 2;
                  final top = (rows - mainRows) ~/ 2;
                  final available = columns - left - mainColumns - 1;
                  final beside = available >= 28;
                  final showChoices =
                      _hasChoices && (_picking || !_hideChoices);
                  final pickerColumns = beside
                      ? available.clamp(28, 40)
                      : mainColumns;
                  final notice = _picking ? box.error ?? box.status : null;
                  final pickerRows = rows.clamp(
                    1,
                    16 +
                        (notice == null
                            ? 0
                            : 1 +
                                  _textRows(
                                    context,
                                    notice,
                                    pickerColumns - 6,
                                  )),
                  );
                  final pickerTop = top.clamp(0, rows - pickerRows);
                  final replaceForm = _picking && !beside;
                  return Stack(
                    children: [
                      Positioned(
                        left: left * _cell,
                        top: (replaceForm ? pickerTop : top) * _rowHeight,
                        width: mainColumns * _cell,
                        height:
                            (replaceForm ? pickerRows : mainRows) * _rowHeight,
                        child: _surface(
                          const ValueKey('new-harness-surface'),
                          _installing != null
                              ? _installPane(_installing!)
                              : replaceForm
                              ? _sidePane()
                              : _items(),
                        ),
                      ),
                      if (showChoices && beside)
                        Positioned(
                          left: (left + mainColumns + 1) * _cell,
                          top: pickerTop * _rowHeight,
                          width: pickerColumns * _cell,
                          height: pickerRows * _rowHeight,
                          child: _surface(
                            const ValueKey('new-harness-chooser-surface'),
                            _sidePane(),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
    return TextSelectionTheme(
      data: TextSelectionThemeData(
        cursorColor: _theme.cursor,
        selectionColor: _theme.selection,
        selectionHandleColor: _theme.cursor,
      ),
      child: widget.desktop
          ? FocusScope(node: _dialogScope, child: form)
          : form,
    );
  }

  Widget _surface(Key key, Widget child) => Material(
    key: key,
    color: _theme.background,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kTerminalCornerRadius),
      side: terminalPaneBorder(focused: true),
    ),
    clipBehavior: Clip.antiAlias,
    child: DefaultTextStyle.merge(style: _ink(), child: child),
  );

  Widget _desktopComposer() => DesktopChrome(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final choosing = _picking;
        final width = constraints.maxWidth.clamp(
          0.0,
          _expanded ? 720.0 : 560.0,
        );
        final folder = box.project.folder;
        final projectName =
            box.project.name ??
            folder
                ?.split(RegExp(r'[/\\]'))
                .where((p) => p.isNotEmpty)
                .lastOrNull ??
            box.project.repository?.name ??
            'Choose project';
        final anchor = _desktopChooserBounds(constraints);
        return Stack(
          key: _desktopCanvasKey,
          children: [
            Align(
              alignment: const Alignment(0, -.12),
              child: SizedBox(
                width: width,
                child: ExcludeFocus(
                  excluding: choosing,
                  child: ExcludeSemantics(
                    excluding: choosing,
                    child: IgnorePointer(
                      ignoring: choosing,
                      child: DesktopDialogSurface(
                        key: const ValueKey('new-harness-surface'),
                        child: FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: SingleChildScrollView(
                            controller: _fieldsScroll,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _desktopHeader(),
                                const SizedBox(height: 20),
                                if (_installing case final run?)
                                  _desktopInstallPane(run)
                                else ...[
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _desktopField(
                                        title: 'Project',
                                        order: 2,
                                        anchor: _desktopAnchors[_Row.project]!,
                                        child: _desktopChoiceButton(
                                          _Row.project,
                                          Icons.folder_outlined,
                                          label: projectName,
                                        ),
                                      ),
                                      _desktopField(
                                        title: 'Agent',
                                        order: 3,
                                        anchor: _desktopAnchors[_Row.agent]!,
                                        child: _desktopChoiceButton(
                                          _Row.agent,
                                          Icons.code_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (box.hasModes || box.canUseWorktree) ...[
                                    const SizedBox(height: 12),
                                    _desktopQuickSettings(),
                                  ],
                                  if (_taskExpanded) ...[
                                    const SizedBox(height: 20),
                                    _desktopTaskEditor(),
                                  ],
                                  if (box.advancedOpen) ...[
                                    const SizedBox(height: 20),
                                    _desktopSettings(),
                                  ] else ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      _desktopSettingsSummary,
                                      key: const ValueKey(
                                        'new-harness-settings-summary',
                                      ),
                                      style: DesktopChrome.text(
                                        size: 12,
                                        color: DesktopChrome.muted,
                                      ),
                                    ),
                                  ],
                                  if (box.requiredChoice
                                      case final required?) ...[
                                    const SizedBox(height: 14),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        required.message,
                                        style: DesktopChrome.text(
                                          size: 13,
                                          color: _theme.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (!choosing &&
                                      (box.error != null ||
                                          box.status != null) &&
                                      box.error !=
                                          box.requiredChoice?.message) ...[
                                    const SizedBox(height: 12),
                                    _status(),
                                  ],
                                  if (box.taskTooLong ||
                                      !box.takesTask &&
                                          box.task.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      box.taskTooLong
                                          ? 'Your message is too long.'
                                          : 'Your task is kept when you switch agents.',
                                      style: DesktopChrome.text(
                                        size: 12,
                                        color: box.taskTooLong
                                            ? _theme.red
                                            : DesktopChrome.muted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  LayoutBuilder(
                                    builder: (context, footer) {
                                      final actions = Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (box.takesTask || _taskExpanded)
                                            FocusTraversalOrder(
                                              order: const NumericFocusOrder(
                                                4.5,
                                              ),
                                              child: DesktopPill(
                                                key: const ValueKey(
                                                  'new-harness-task-toggle',
                                                ),
                                                focusNode: _taskToggleFocus,
                                                label: !_taskExpanded
                                                    ? 'Add task'
                                                    : box.task.isEmpty
                                                    ? 'Hide task'
                                                    : 'Edit task',
                                                icon: Icons.notes_rounded,
                                                selected: _taskExpanded,
                                                onPressed: box.locked
                                                    ? null
                                                    : _toggleDesktopTask,
                                              ),
                                            ),
                                          FocusTraversalOrder(
                                            order: const NumericFocusOrder(5),
                                            child: DesktopPill(
                                              key: const ValueKey(
                                                'new-harness-field-advanced',
                                              ),
                                              focusNode:
                                                  _desktopFocus[_Row.advanced],
                                              label: 'Options',
                                              icon: Icons.tune_rounded,
                                              selected: box.advancedOpen,
                                              onPressed: box.locked
                                                  ? null
                                                  : _toggleAdvanced,
                                            ),
                                          ),
                                        ],
                                      );
                                      if (footer.maxWidth <
                                          400 *
                                              MediaQuery.textScalerOf(context)
                                                  .scale(1)) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            actions,
                                            const SizedBox(height: 12),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: _desktopStartButton(),
                                            ),
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(child: actions),
                                          const SizedBox(width: 12),
                                          _desktopStartButton(),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (choosing) ...[
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('new-harness-chooser-dismiss'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _closeDesktopChooser(),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned.fromRect(
                rect: anchor,
                child: DesktopDialogSurface(
                  key: const ValueKey('new-harness-chooser-surface'),
                  radius: 12,
                  child: _desktopChooser(),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _desktopHeader() => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        'New harness',
        style: DesktopChrome.text(size: 20, medium: true),
      );
      final machine = _desktopField(
        order: 1,
        anchor: _machineAnchor,
        child: DesktopPill(
          key: const ValueKey('new-harness-machine'),
          focusNode: _machineFocus,
          label: box.machineLabel,
          semanticLabel: 'Machine, ${box.machineLabel}',
          tooltip: 'Machine: ${box.machineLabel}',
          icon: Icons.laptop_mac_rounded,
          menu: true,
          onPressed: box.locked ? null : _openMachineChooser,
        ),
      );
      final close = FocusTraversalOrder(
        // Start is last, so Tab wraps directly to Machine.
        order: const NumericFocusOrder(9.9),
        child: IconButton(
          key: const ValueKey('new-harness-close'),
          tooltip: 'Close new harness',
          onPressed: () {
            if (box.requestDismiss()) {
              widget.onClose();
            }
          },
          icon: const Icon(Icons.close_rounded, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      );
      if (constraints.maxWidth <
          480 * MediaQuery.textScalerOf(context).scale(1)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: title),
                close,
              ],
            ),
            const SizedBox(height: 12),
            machine,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: machine,
          ),
          const SizedBox(width: 8),
          close,
        ],
      );
    },
  );

  void _toggleDesktopTask() {
    if (_taskExpanded && box.task.isEmpty) {
      setState(() => _taskExpanded = false);
      _chooserOrigin = _taskToggleFocus;
      _restoreChoiceFocus = true;
      _chooserTraversal = null;
      _focusEditor();
    } else {
      _creationTask();
    }
  }

  String get _desktopSettingsSummary => [
    if (!box.isTerminal) box.modelLabel,
    if (box.isGitProject) box.branchRowLabel,
    if (box.usesProfile && box.profileLabel != null) box.profileLabel!,
  ].join(' · ');

  Widget _desktopTaskEditor() => Material(
    key: const ValueKey('new-harness-composer'),
    color: DesktopChrome.field,
    shape: DesktopChrome.shape(radius: 10),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(4),
        child: TextField(
          key: const ValueKey('new-harness-task'),
          controller: _taskText,
          focusNode: _taskFocus,
          minLines: 3,
          maxLines: 7,
          readOnly: box.locked || !box.takesTask,
          style: DesktopChrome.text(size: 15),
          cursorColor: DesktopChrome.accent,
          onChanged: box.setTask,
          onTapOutside: (_) {},
          decoration: InputDecoration(
            hintText: box.takesTask
                ? 'What would you like to work on?'
                : 'Open a terminal in this project',
            hintStyle: DesktopChrome.text(size: 15, color: DesktopChrome.muted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isCollapsed: true,
            filled: false,
          ),
        ),
      ),
    ),
  );

  Widget _desktopQuickSettings() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (box.hasModes)
        _desktopField(
          order: 3.5,
          anchor: _desktopAnchors[_Row.approvals]!,
          child: _desktopChoiceButton(
            _Row.approvals,
            Icons.verified_user_outlined,
          ),
        ),
      if (box.canUseWorktree)
        _desktopField(
          order: 3.6,
          anchor: _desktopAnchors[_Row.worktree]!,
          child: DesktopPill(
            key: const ValueKey('new-harness-field-worktree'),
            focusNode: _desktopFocus[_Row.worktree],
            label: 'New worktree',
            icon: box.worktree
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            selected: box.worktree,
            tooltip: 'Keep this task in its own Git worktree',
            onPressed: box.locked ? null : box.toggleWorktree,
          ),
        ),
    ],
  );

  Widget _desktopSettings() => Wrap(
    key: const ValueKey('new-harness-settings'),
    spacing: 12,
    runSpacing: 12,
    children: [
      if (box.isGitProject || box.checkingGit || box.gitError != null)
        _desktopField(
          title: 'Branch',
          order: 6,
          anchor: _desktopAnchors[_Row.branch]!,
          child: _desktopChoiceButton(
            _Row.branch,
            Icons.account_tree_outlined,
            mono: true,
          ),
        ),
      if (!box.isTerminal)
        _desktopField(
          title: 'Model',
          order: 7,
          anchor: _desktopAnchors[_Row.model]!,
          child: _desktopChoiceButton(_Row.model, Icons.auto_awesome_outlined),
        ),
      if (box.usesProfile)
        _desktopField(
          title: 'Codex profile',
          order: 9.5,
          anchor: _desktopAnchors[_Row.profile]!,
          child: _desktopChoiceButton(
            _Row.profile,
            Icons.person_outline_rounded,
          ),
        ),
      if (box.isTerminal &&
          !box.isGitProject &&
          !box.checkingGit &&
          box.gitError == null)
        Text(
          'No additional options for this folder.',
          style: DesktopChrome.text(size: 13, color: DesktopChrome.muted),
        ),
    ],
  );

  Widget _desktopField({
    required double order,
    required GlobalKey anchor,
    required Widget child,
    String? title,
  }) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: ConstrainedBox(
      key: anchor,
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
            ),
            const SizedBox(height: 5),
          ],
          child,
        ],
      ),
    ),
  );

  Widget _desktopChoiceButton(
    _Row row,
    IconData icon, {
    String? label,
    bool mono = false,
  }) => DesktopPill(
    key: ValueKey('new-harness-field-${row.name}'),
    focusNode: _desktopFocus[row],
    label: label ?? _value(row),
    semanticLabel: '${_label(row)}, ${label ?? _value(row)}',
    icon: icon,
    menu: true,
    monospace: mono,
    tooltip: '${_label(row)}: ${_blocked(row) ?? _value(row)}',
    onPressed: box.locked || _blocked(row) != null
        ? null
        : () => _activateRow(row),
  );

  Widget _desktopStartButton() {
    final shortcut = !_taskExpanded
        ? '↵'
        : effectiveCommandHint(
            context,
            'picker.add_here',
            contextKind: KeymapContext.picker,
          );
    final label = box.busy
        ? (_checkingLaunch ? 'Checking…' : 'Starting…')
        : box.checking
        ? 'Check status'
        : 'Start';
    return FocusTraversalOrder(
      order: const NumericFocusOrder(10),
      child: FilledButton(
        key: const ValueKey('new-harness-field-start'),
        focusNode: _desktopFocus[_Row.start],
        onPressed: _desktopStartEnabled ? _start : null,
        style:
            FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(90, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: DesktopChrome.text(size: 13, medium: true),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? DesktopChrome.focusRing
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (box.busy) ...[
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(label),
            if (shortcut != null && !box.busy) ...[
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Text(
                  shortcut,
                  style: grid.AppType.monoMeta(
                    color: Colors.white.withValues(alpha: .8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Rect _desktopChooserBounds(BoxConstraints constraints) {
    final width = (constraints.maxWidth - 24).clamp(0.0, 480.0);
    final height = (constraints.maxHeight - 24).clamp(0.0, 460.0);
    final canvas = _desktopCanvasKey.currentContext?.findRenderObject();
    final target = _chooserAnchor?.currentContext?.findRenderObject();
    var left = (constraints.maxWidth - width) / 2;
    var top = (constraints.maxHeight - height) / 2;
    if (canvas is RenderBox &&
        target is RenderBox &&
        target.hasSize &&
        canvas.hasSize) {
      final origin = target.localToGlobal(Offset.zero, ancestor: canvas);
      left = origin.dx.clamp(
        12.0,
        (constraints.maxWidth - width - 12).clamp(12.0, double.infinity),
      );
      final below = origin.dy + target.size.height + 8;
      if (below + height <= constraints.maxHeight - 12) {
        top = below;
      } else if (origin.dy - height - 8 >= 12) {
        top = origin.dy - height - 8;
      }
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  String get _desktopChooserTitle => switch (box.field) {
    NewHarnessField.machine => 'Choose machine',
    NewHarnessField.projectMenu => 'Choose project',
    NewHarnessField.project => 'Open folder',
    NewHarnessField.projectName => 'New folder',
    NewHarnessField.projectRepository => 'Clone repository',
    NewHarnessField.agent => 'Run ${box.harnessLabel} with',
    NewHarnessField.harness => 'Choose agent',
    NewHarnessField.model => 'Choose model',
    NewHarnessField.mode => 'Approvals',
    NewHarnessField.profile => 'Codex profile',
    NewHarnessField.branch => 'Choose branch',
    _ => 'Choose an option',
  };

  Widget _desktopChooser() => Semantics(
    key: const ValueKey('new-harness-choices'),
    container: true,
    explicitChildNodes: true,
    focused: true,
    label: _desktopChooserTitle,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              ExcludeFocus(
                child: IconButton(
                  key: const ValueKey('new-harness-chooser-back'),
                  tooltip: 'Back',
                  onPressed: box.locked ? null : () => _runCommand(_cancel),
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(
                child: Text(
                  _desktopChooserTitle,
                  style: DesktopChrome.text(size: 14, medium: true),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ExcludeFocus(
                child: IconButton(
                  key: const ValueKey('new-harness-chooser-close'),
                  tooltip: 'Close choices',
                  onPressed: box.locked ? null : () => _closeDesktopChooser(),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: ListenableBuilder(
            listenable: _inputFocus,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: DesktopChrome.field,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _inputFocus.hasFocus
                      ? DesktopChrome.focusRing
                      : DesktopChrome.rim,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: _searchBar(),
              ),
            ),
          ),
        ),
        if (_prompts.contains(box.field))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'On ${box.machineLabel}',
              style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
            ),
          ),
        if (box.choicesStatus case final status?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
              ),
            ),
          ),
        if (_row == _Row.model && box.modelNotice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              box.modelNotice!,
              style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
            ),
          ),
        Divider(height: 1, color: DesktopChrome.rim),
        Expanded(
          child: box.options.isEmpty && !box.refreshingChoices
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _prompts.contains(box.field)
                          ? 'Enter ${box.field == NewHarnessField.projectRepository
                                ? 'a repository URL'
                                : box.field == NewHarnessField.projectName
                                ? 'a folder name'
                                : 'a folder path'} above.'
                          : 'No matches. Try another search.',
                      style: DesktopChrome.text(
                        size: 13,
                        color: DesktopChrome.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _choicesScroll,
                  child: ListView.builder(
                    controller: _choicesScroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    itemCount: box.options.length,
                    itemExtentBuilder: (i, _) => _desktopChoiceHeight(i),
                    itemBuilder: (context, i) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_headingBefore(i))
                          SizedBox(
                            height: _desktopGroupHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  box.options[i].group!,
                                  style: DesktopChrome.text(
                                    size: 11,
                                    medium: true,
                                    color: DesktopChrome.muted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        Expanded(child: _desktopOption(box.options[i])),
                      ],
                    ),
                  ),
                ),
        ),
        if (box.error != null || box.status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: _status(),
          ),
        Divider(height: 1, color: DesktopChrome.rim),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 18,
            runSpacing: 5,
            children: [
              for (final hint in [
                ('picker.next', 'Browse'),
                ('picker.accept', 'Select'),
                ('picker.cancel', 'Back'),
              ])
                if (effectiveCommandHint(
                      context,
                      hint.$1,
                      contextKind: KeymapContext.picker,
                    )
                    case final keys?)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: keys,
                          style: grid.AppType.monoMeta(
                            color: DesktopChrome.muted,
                          ),
                        ),
                        TextSpan(text: '  ${hint.$2}'),
                      ],
                    ),
                    style: DesktopChrome.text(
                      size: 11,
                      color: DesktopChrome.muted,
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );

  double _desktopLineHeight(String text, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DesktopChrome.text(size: size),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return height;
  }

  double get _desktopGroupHeight => _desktopLineHeight('Ag', 11) + 12;
  double _desktopChoiceHeight(int i) =>
      16 +
      _desktopLineHeight(_desktopOptionTitle(box.options[i]), 13) +
      (_desktopOptionDetail(box.options[i]).isEmpty
          ? 0
          : 3 + _desktopLineHeight(_desktopOptionDetail(box.options[i]), 12)) +
      (_headingBefore(i) ? _desktopGroupHeight : 0);

  String _desktopOptionTitle(NewHarnessOption option) {
    final folder = option.project?.folder;
    if (box.field == NewHarnessField.projectMenu && folder != null) {
      return folder
              .split(RegExp(r'[/\\]'))
              .where((part) => part.isNotEmpty)
              .lastOrNull ??
          folder;
    }
    return option.title;
  }

  String _desktopOptionDetail(NewHarnessOption option) {
    final machine = box.app
        .stateOf(option.machineId ?? box.machineId)
        ?.machine
        .displayName;
    if (machine != null && option.detail.startsWith('$machine:')) {
      return '$machine · ${option.detail.substring(machine.length + 1)}';
    }
    return option.detail;
  }

  IconData _desktopOptionIcon(NewHarnessOption option) {
    if (option.id == NewHarnessController.newProjectId) {
      return Icons.create_new_folder_outlined;
    }
    if (option.id == NewHarnessController.repositoryId) {
      return Icons.cloud_download_outlined;
    }
    if (option.id == NewHarnessController.browseId ||
        option.id == NewHarnessController.existingProjectId) {
      return Icons.folder_open_rounded;
    }
    if (option.id == NewHarnessController.changeMachineId) {
      return Icons.computer_rounded;
    }
    if (option.id == NewHarnessController.refreshProfilesId ||
        option.id == NewHarnessController.refreshModelsId) {
      return Icons.refresh_rounded;
    }
    if (option.id == NewHarnessController.linkProfileId) {
      return Icons.add_rounded;
    }
    if (option.id == NewHarnessController.storeId) return Icons.apps_rounded;
    return switch (box.field) {
      NewHarnessField.machine => Icons.computer_rounded,
      NewHarnessField.branch => Icons.account_tree_outlined,
      NewHarnessField.projectMenu ||
      NewHarnessField.project ||
      NewHarnessField.projectName => Icons.folder_outlined,
      NewHarnessField.projectRepository => Icons.cloud_download_outlined,
      NewHarnessField.model => Icons.auto_awesome_outlined,
      NewHarnessField.profile => Icons.person_outline_rounded,
      NewHarnessField.mode => Icons.verified_user_outlined,
      _ => Icons.code_rounded,
    };
  }

  Widget _desktopOption(NewHarnessOption option) {
    final title = _desktopOptionTitle(option);
    final detail = _desktopOptionDetail(option);
    final highlighted = identical(option, box.selected);
    final current = box.isCurrent(option) && !_isDoor(option);
    final note = !option.enabled
        ? option.why
        : box.field == NewHarnessField.machine
        ? _machineNote(option.id)
        : null;
    return Semantics(
      key: ValueKey('new-harness-option-${option.id}'),
      selected: highlighted,
      enabled: option.enabled && !box.locked,
      button: true,
      value: current ? 'Current selection' : null,
      hint: _unlinked(option) ? 'Link required' : null,
      child: Tooltip(
        message: [title, if (detail.isNotEmpty) detail, ?note].join('\n'),
        child: Material(
          color: highlighted ? DesktopChrome.selection : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(7),
            hoverColor: DesktopChrome.foreground.withValues(alpha: .06),
            splashFactory: NoSplash.splashFactory,
            onTap: !box.locked ? () => _acceptChoice(option) : null,
            child: Padding(
              key: highlighted ? _choiceKey : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _desktopOptionIcon(option),
                    size: 18,
                    color: option.enabled
                        ? DesktopChrome.muted
                        : DesktopChrome.muted.withValues(alpha: .6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: DesktopChrome.text(
                            size: 13,
                            color: option.enabled
                                ? DesktopChrome.foreground
                                : DesktopChrome.muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            detail,
                            style: DesktopChrome.text(
                              size: 12,
                              color: DesktopChrome.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (note?.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 95),
                      child: Text(
                        note!,
                        style: DesktopChrome.text(
                          size: 11,
                          color: DesktopChrome.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    child: current
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: DesktopChrome.accent,
                          )
                        : _isDoor(option)
                        ? Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: DesktopChrome.muted,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopInstallPane(DshInstallRun run) => Semantics(
    key: const ValueKey('new-harness-install'),
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          run.failed
              ? '${box.harnessLabel} could not be installed'
              : run.done
              ? '${box.harnessLabel} is ready'
              : 'Setting up ${box.harnessLabel}',
          style: DesktopChrome.text(size: 16, medium: true),
        ),
        const SizedBox(height: 6),
        Text(
          'On ${box.machineLabel}',
          style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
        ),
        const SizedBox(height: 20),
        for (final (phase, label) in [
          ('clone', 'Download harness'),
          ('setup', 'Set up tools'),
          ('doctor', 'Check requirements'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(
                  run.done || (run.reached(phase) && run.phase != phase)
                      ? Icons.check_circle_outline_rounded
                      : run.failed
                      ? Icons.error_outline_rounded
                      : Icons.circle_outlined,
                  size: 18,
                  color: run.failed ? _theme.red : DesktopChrome.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: DesktopChrome.text(size: 13)),
                ),
                if (run.took(phase) case final duration?)
                  Text(
                    _took(duration),
                    style: DesktopChrome.text(
                      size: 12,
                      color: DesktopChrome.muted,
                    ),
                  ),
              ],
            ),
          ),
        if (run.failed) ...[
          const SizedBox(height: 12),
          Text(
            describeInstallFailure(run, box.harnessLabel).title,
            style: DesktopChrome.text(size: 13, color: _theme.red),
          ),
          if (describeInstallFailure(run, box.harnessLabel).body
              case final body?)
            Text(
              body,
              style: DesktopChrome.text(size: 13, color: DesktopChrome.muted),
            ),
          if (describeInstallFailure(run, box.harnessLabel).command
              case final command?)
            SelectableText(command, style: grid.AppType.mono()),
          if (describeInstallFailure(run, box.harnessLabel).hint
              case final hint?)
            Text(
              hint,
              style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
            ),
        ] else if (run.line ?? run.detail case final status?) ...[
          const SizedBox(height: 12),
          Text(
            status,
            style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Elapsed(
                run: run,
                style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
              ),
            ),
            _desktopStartButton(),
          ],
        ),
      ],
    ),
  );

  Widget _items() => Padding(
    padding: EdgeInsets.fromLTRB(_margin, _rowHeight, _margin, _rowHeight),
    child: Scrollbar(
      controller: _fieldsScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _fieldsScroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in _rows.where((row) => row != _Row.start)) ...[
              // Blank rows are part of the grid, never flexible spacers.
              if (row == _Row.project || row == _Row.advanced)
                SizedBox(height: _rowHeight),
              _buildRow(row),
            ],
            if (box.task.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: _oneRow(
                  Row(
                    children: [
                      SizedBox(
                        width: _cell * (_labelCells + _labelGapCells),
                        child: Text('Task', style: _ink(_faint)),
                      ),
                      Expanded(
                        child: Tooltip(
                          message: box.task,
                          child: Text(
                            box.task,
                            style: _ink(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _buildButton(),
            if (!_picking && box.requiredChoice != null) ...[
              SizedBox(height: _rowHeight),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: Text(
                  box.requiredChoice!.message,
                  style: _ink(_theme.red),
                ),
              ),
            ],
            if (!_picking &&
                (box.error != null || box.status != null) &&
                (box.error == null ||
                    box.error != box.requiredChoice?.message)) ...[
              SizedBox(height: _rowHeight),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: _status(),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  /// The launch action uses plain text on the label column and the same
  /// single-row highlight as the fields. It is selected when the form opens.
  Widget _buildButton() {
    final on = box.busy || (_row == _Row.start && !_picking);
    final label = box.busy
        ? (_checkingLaunch ? 'Checking...' : 'Starting...')
        : _value(_Row.start);
    return Semantics(
      key: const ValueKey('new-harness-field-start'),
      container: true,
      button: true,
      label: label,
      liveRegion: box.busy,
      excludeSemantics: true,
      selected: on,
      enabled: !box.busy && !box.linkingProfile && box.requiredChoice == null,
      onTap: !box.busy && !box.linkingProfile && box.requiredChoice == null
          ? _start
          : null,
      child: Padding(
        key: _itemKeys[_Row.start],
        // One blank row between the last field and the action.
        padding: EdgeInsets.only(top: _rowHeight),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: !box.busy && !box.linkingProfile && box.requiredChoice == null
              ? _start
              : null,
          child: Container(
            color: on ? _activeFill : Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: _margin),
            height: _rowHeight,
            alignment: Alignment.centerLeft,
            child: box.busy
                ? _LaunchProgress(label: label, style: _ink(_theme.foreground))
                : Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: _ink(
                      box.requiredChoice != null || _picking
                          ? _faint
                          : _theme.foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// The chooser uses the same frame, font, and cell origin as the form.
  Widget _sidePane() => Semantics(
    key: const ValueKey('new-harness-choices'),
    container: true,
    focused: _picking,
    label: '${_label(_row)} choices',
    child: Padding(
      padding: EdgeInsets.fromLTRB(_margin, _rowHeight, _margin, _rowHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasChoices) ...[
            if ((box.field == NewHarnessField.machine &&
                    _folderAction != null) ||
                _prompts.contains(box.field)) ...[
              _atTextColumn(
                Text(
                  box.field == NewHarnessField.machine
                      ? switch (_folderAction) {
                          NewHarnessController.newProjectId => 'New Folder',
                          NewHarnessController.repositoryId =>
                            'Clone Repository',
                          _ => 'Open Folder',
                        }
                      : box.field == NewHarnessField.projectName
                      ? '${box.machineLabel}:~/harnesses'
                      : box.machineLabel,
                  style: _ink(_faint),
                ),
              ),
              SizedBox(height: _rowHeight),
            ],
            _searchBar(),
            if (box.choicesStatus case final status?)
              _atTextColumn(
                Semantics(
                  liveRegion: true,
                  child: Text(status, style: _ink(_faint)),
                ),
              ),
            SizedBox(height: _rowHeight),
            Flexible(
              child: Scrollbar(
                controller: _choicesScroll,
                thumbVisibility: true,
                child: _matchPane(),
              ),
            ),
          ],
          if (_picking && (box.error != null || box.status != null)) ...[
            SizedBox(height: _rowHeight),
            _atTextColumn(_status()),
          ],
        ],
      ),
    ),
  );

  /// The install start is waiting on, while the list is not in use: once
  /// someone opens a list again, its choices matter more than the narration.
  DshInstallRun? get _installing => _picking ? null : box.installRun;

  /// What the machine says while it installs the harness start asked for —
  /// fetch, set up, check — drawn on the grid like every other line here:
  /// one glyph in the pointer column, text on the text column, one row each.
  /// The machine's words, never a progress bar, because it gives no percent.
  Widget _installPane(DshInstallRun run) {
    final name = box.harnessLabel;
    final steps = [
      ('clone', 'Fetch $name'),
      ('setup', 'Set up the toolchain'),
      ('doctor', 'Check this machine'),
    ];
    final failedPhase = run.failed && run.phases.length >= 2
        ? run.phases[run.phases.length - 2].phase
        : null;
    final failure = run.failed ? describeInstallFailure(run, name) : null;
    Widget line(String? glyph, String text, {Color? color, Widget? end}) =>
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _margin),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inGutter(
                glyph == null ? null : _oneRow(Text(glyph, style: _ink(color))),
              ),
              Expanded(child: Text(text, style: _ink(color))),
              ?end,
            ],
          ),
        );
    final tail = run.log.length > 6
        ? run.log.sublist(run.log.length - 6)
        : run.log;
    return Semantics(
      key: const ValueKey('new-harness-install'),
      container: true,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _rowHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                null,
                run.done
                    ? '$name installed on ${box.machineLabel}'
                    : run.failed
                    ? '$name did not install on ${box.machineLabel}'
                    : 'Installing $name on ${box.machineLabel}',
                end: _Elapsed(run: run, style: _ink(_faint)),
              ),
              SizedBox(height: _rowHeight),
              for (final (phase, label) in steps) ...[
                if (failedPhase == phase)
                  line('✗', label, color: _theme.red)
                else if (run.done || (run.reached(phase) && run.phase != phase))
                  line(
                    '✓',
                    label,
                    end: run.took(phase) == null
                        ? null
                        : Text(_took(run.took(phase)!), style: _ink(_faint)),
                  )
                else if (run.phase == phase && run.inProgress) ...[
                  line('>', label),
                  if (run.line ?? run.detail case final now?)
                    line(null, now, color: _faint),
                ] else
                  line(' ', label, color: _faint),
              ],
              if (tail.isNotEmpty && !run.done && failure == null) ...[
                SizedBox(height: _rowHeight),
                for (final entry in tail) line(null, entry, color: _faint),
              ],
              if (failure != null) ...[
                SizedBox(height: _rowHeight),
                line(null, failure.title, color: _theme.red),
                if (failure.body case final body?)
                  line(null, body, color: _faint),
                if (failure.command case final command?) line(null, command),
                if (failure.hint case final hint?)
                  line(null, hint, color: _faint),
              ],
              SizedBox(height: _rowHeight),
              line(
                null,
                run.failed
                    ? 'What was downloaded is kept. Enter tries again.'
                    : run.done
                    ? 'Starting the harness…'
                    : 'The first install takes a few minutes.',
                color: _faint,
              ),
              SizedBox(height: _rowHeight),
              _buildButton(),
            ],
          ),
        ),
      ),
    );
  }

  static String _took(Duration d) => d.inSeconds < 60
      ? '${d.inSeconds}s'
      : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _status() => Semantics(
    liveRegion: true,
    child: Text(
      box.error ?? box.status!,
      key: const ValueKey('new-harness-status'),
      style: _ink(box.error != null ? _theme.red : _faint),
    ),
  );

  /// Whether this row has anything to list. Worktree is a boolean and the
  /// button is an action, so their columns stay empty rather than inventing
  /// something to fill them.
  bool get _hasChoices => _fieldOf(_row) != null && _blocked(_row) == null;

  /// The choices, in the order the controller already ranks them: the three
  /// doors first — New Project, Open Folder, Clone — then the recents and
  /// matches under a gap. The highlight opens on the first real project, the
  /// fourth row, so the doors are visible without being in the way.
  bool _headingBefore(int i) =>
      box.options[i].group != null &&
      (i == 0 || box.options[i].group != box.options[i - 1].group);
  bool _blankBefore(int i) =>
      i > 0 &&
      (_headingBefore(i) ||
          _showsDetail(box.options[i - 1]) ||
          (box.options[i - 1].synthetic && !box.options[i].synthetic));
  int _choiceLines(int i) =>
      1 +
      (_headingBefore(i) ? 1 : 0) +
      (_blankBefore(i) ? 1 : 0) +
      (_showsDetail(box.options[i]) ? 1 : 0);

  Widget _matchPane() {
    final shown = box.options;
    // At most ONE blank row before an entry, whatever asks for it: a new
    // heading, the end of a two-row entry, or the doors giving way to the
    // projects. Adding each reason's own gap is how two blanks appeared.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_row == _Row.model && box.modelNotice != null) ...[
          _atTextColumn(Text(box.modelNotice!, style: _ink(_faint))),
          SizedBox(height: _rowHeight),
        ],
        if (shown.isEmpty &&
            !_prompts.contains(box.field) &&
            !box.refreshingChoices)
          _atTextColumn(Text('No matches', style: _ink(_faint))),
        Expanded(
          child: ListView.builder(
            controller: _choicesScroll,
            itemCount: shown.length,
            itemExtentBuilder: (i, _) => _choiceLines(i) * _rowHeight,
            itemBuilder: (context, i) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_blankBefore(i)) SizedBox(height: _rowHeight),
                if (_headingBefore(i))
                  _oneRow(
                    _atTextColumn(Text(shown[i].group!, style: _ink(_faint))),
                  ),
                _matchRow(shown[i]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A line that is not a choice — a heading, a notice, a status — starts on
  /// the same column as the names below it, so each pane has one left edge.
  Widget _atTextColumn(Widget child) => Padding(
    padding: EdgeInsets.only(left: _margin + _gutter, right: _margin),
    child: child,
  );

  /// The pointer column's two cells, holding a glyph centred in them, so the
  /// prompt's `>` and every row's icon share one x.
  Widget _inGutter(Widget? child) => SizedBox(
    width: _gutter,
    child: child == null ? null : Center(child: child),
  );

  /// A prompt people can see, because "type to search" printed in a key
  /// guide is a sentence nobody reads. fzf's `>` rather than a labelled box:
  /// there is no second place for the caret to be, so it needs no border.
  /// What the prompt is actually for. A path prompt is not a search — it
  /// wants a folder typed at it — so it borrows the controller's own words
  /// rather than calling everything "Search".
  String get _promptHint => box.field == NewHarnessField.agent
      ? 'Run ${box.harnessLabel} with'
      : box.hint;

  Widget _searchBar() {
    return Padding(
      key: _searchKey,
      padding: EdgeInsets.symmetric(horizontal: _margin),
      child: Row(
        crossAxisAlignment: widget.desktop
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: widget.desktop ? 20 : _gutter,
            child: widget.desktop
                ? Icon(Icons.search_rounded, size: 18, color: _faint)
                : Text(
                    '>',
                    key: const ValueKey('new-harness-prompt'),
                    textAlign: TextAlign.center,
                    style: _ink(_picking ? _theme.foreground : _faint),
                  ),
          ),
          if (widget.desktop) const SizedBox(width: 8),
          Expanded(
            child: Actions(
              actions: {
                PasteTextIntent: CallbackAction<PasteTextIntent>(
                  onInvoke: (_) {
                    unawaited(_pasteQuery());
                    return null;
                  },
                ),
              },
              child: TextField(
                key: const ValueKey('new-harness-query'),
                controller: _queryText,
                focusNode: _inputFocus,
                readOnly: box.locked,
                showCursor: _picking,
                style: _ink(_theme.foreground),
                cursorColor: widget.desktop
                    ? DesktopChrome.foreground
                    : _theme.cursor,
                cursorWidth: 2,
                cursorRadius: Radius.zero,
                cursorOpacityAnimates: false,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _onTyped,
                onTap: () {
                  setState(() => _listOpen = true);
                  _revealRow();
                },
                onTapOutside: (_) {},
                decoration: InputDecoration(
                  hintText: _promptHint,
                  hintStyle: _ink(_faint),
                  hintMaxLines: 1,
                  isDense: true,
                  isCollapsed: true,
                  constraints: const BoxConstraints(),
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          if (box.canRefreshChoices)
            // Held to two cells by one row: a Material button's 48px tap
            // target would make the prompt taller than every other line.
            Tooltip(
              message: 'Refresh results',
              child: InkWell(
                key: const ValueKey('new-harness-refresh'),
                canRequestFocus: false,
                onTap: box.refreshingChoices ? null : box.refreshChoices,
                child: widget.desktop
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: _faint,
                        ),
                      )
                    : Text('[ Refresh ]', style: _ink(_faint)),
              ),
            ),
        ],
      ),
    );
  }

  /// The word at the right of a machine row.
  ///
  /// A row that cannot be chosen has to SAY so: dimmed text alone reads as a
  /// theme, and the reason — offline, or never linked — is the one thing the
  /// person needs in order to do something about it. Machine rows are the only
  /// ones that carry a note, so "This machine" keeps the slot when there is no
  /// bad news to put in it.
  String? _machineNote(String machineId) {
    final machine = box.app.stateOf(machineId);
    if (machine == null) return null;
    // Not linked: said by colour, not a word (see [_unlinked]).
    if (machine.needsLink) return null;
    if (machine.isOffline) return 'Offline';
    return machine.isLocalMachine ? 'This machine' : null;
  }

  /// Whether a choice carries a description under its name.
  bool _showsDetail(NewHarnessOption option) =>
      (_row == _Row.model || _row == _Row.profile) &&
      option.detail.isNotEmpty &&
      !_isDoor(option);

  /// A machine this computer has not linked yet. On screen it looks like
  /// any other machine that cannot be picked (see [_unavailableInk]); the
  /// difference is kept for screen readers, which hear "Link required", and
  /// an offline machine keeps its printed word.
  bool _unlinked(NewHarnessOption option) =>
      box.field == NewHarnessField.machine &&
      box.app.stateOf(option.id)?.needsLink == true;

  Widget _matchRow(NewHarnessOption option) {
    final on = identical(option, box.selected);
    final note = box.field == NewHarnessField.projectMenu && !option.enabled
        ? option.why
        : box.field == NewHarnessField.machine
        ? _machineNote(option.id)
        : null;
    final showDetail = _showsDetail(option);
    final unlinked = _unlinked(option);
    final unavailable = !option.enabled;
    final title = Text(
      option.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _ink(
        unavailable
            ? _unavailableInk
            : !_picking || !option.enabled
            ? _faint
            : option.synthetic
            ? _theme.cursor
            : _theme.foreground,
      ),
    );
    return Semantics(
      key: ValueKey('new-harness-option-${option.id}'),
      // Colour is not announced, so the word the row no longer prints is
      // still what a screen reader says.
      hint: unlinked
          ? 'Link required'
          : _row == _Row.agent && option.detail.isNotEmpty
          ? option.detail
          : null,
      selected: on,
      enabled: option.enabled && !box.locked,
      button: _isDoor(option),
      child: InkWell(
        canRequestFocus: false,
        onTap: !box.locked ? () => _acceptChoice(option) : null,
        child: Column(
          key: on ? _choiceKey : null,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The bar covers the NAME, one row, and stops there. Filling the
            // description with it made the selection two rows tall and the
            // list read as blocks rather than lines.
            Container(
              color: on && _picking ? _activeFill : Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: _margin),
              height: _rowHeight,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // The pointer column stays, empty, so names keep one edge
                  // with the prompt's text.
                  _inGutter(null),
                  Expanded(child: title),
                  // Main's note says WHY a machine cannot be chosen — offline,
                  // or never linked — which a dimmed row alone cannot.
                  if (note != null) ...[
                    SizedBox(width: _cell * 2),
                    Text(note, style: _ink(_faint)),
                  ],
                ],
              ),
            ),
            if (showDetail)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: Row(
                  children: [
                    _inGutter(null),
                    Expanded(
                      child: _oneRow(
                        Text(
                          option.detail,
                          style: _ink(_faint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _selectRow(_Row row) {
    if (box.locked) return;
    setState(() {
      _row = row;
      _listOpen = false;
      _hideChoices = false;
    });
    box.setQuery('');
    _syncField();
    _focus.requestFocus();
    _focusEditor();
    _revealRow();
  }

  void _activateRow(_Row row) {
    if (widget.desktop) {
      _chooserOrigin = _desktopFocus[row];
      _chooserAnchor = _desktopAnchors[row];
      _restoreChoiceFocus = false;
    }
    _selectRow(row);
    if (row == _Row.advanced) {
      _toggleAdvanced();
    } else if (row == _Row.worktree) {
      box.toggleWorktree();
    } else {
      setState(() => _listOpen = true);
    }
    _focusEditor();
    _revealRow();
  }

  void _toggleAdvanced() {
    if (box.locked) return;
    box.toggleAdvanced();
    setState(() {
      _row = _Row.advanced;
      _listOpen = false;
      _hideChoices = false;
    });
    box.setQuery('');
    if (widget.desktop) {
      _chooserOrigin = _desktopFocus[_Row.advanced];
      _restoreChoiceFocus = true;
      _chooserTraversal = null;
    }
    _focusEditor();
    _revealRow();
  }

  Widget _buildRow(_Row row) {
    final highlighted = row == _row;
    final blocked = _blocked(row);
    final value = blocked ?? _value(row);
    final ink = blocked != null || _picking ? _faint : _theme.foreground;
    return Semantics(
      key: ValueKey('new-harness-field-${row.name}'),
      label: '${_label(row)}, $value',
      selected: highlighted,
      enabled: blocked == null && !box.locked,
      onTap: blocked == null && !box.locked ? () => _activateRow(row) : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: blocked == null && !box.locked ? () => _activateRow(row) : null,
        child: MouseRegion(
          cursor: blocked == null && !box.locked
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            key: _itemKeys[row],
            color: highlighted
                ? (_picking ? _idleFill : _activeFill)
                : Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: _margin),
            height: _rowHeight,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                SizedBox(
                  width: _cell * _labelCells,
                  child: Text(_label(row), style: _ink(_faint)),
                ),
                SizedBox(width: _cell * _labelGapCells),
                Expanded(
                  child: Text(
                    value,
                    style: _ink(ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An install's running clock, ticking itself so the form does not rebuild
/// every second. Disposed with the install pane.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.run, required this.style});

  final DshInstallRun run;
  final TextStyle style;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.run.inProgress) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final end = run.inProgress || run.phases.isEmpty
        ? DateTime.now()
        : run.phases.last.at;
    final d = end.difference(run.startedAt);
    return Text(
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
      style: widget.style,
    );
  }
}

/// Animate only the busy action, at terminal speed, without rebuilding the form.
class _LaunchProgress extends StatefulWidget {
  const _LaunchProgress({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  State<_LaunchProgress> createState() => _LaunchProgressState();
}

class _LaunchProgressState extends State<_LaunchProgress> {
  static const _frames = ['|', '/', '-', '\\'];
  Timer? _timer;
  int _frame = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 160), (_) {
        setState(() => _frame = (_frame + 1) % _frames.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${_frames[_frame]} ${widget.label}',
    key: const ValueKey('new-harness-progress'),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
    style: widget.style,
  );
}
