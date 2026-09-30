import 'dart:async';

import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/app_dialog.dart';
import '../widgets/desktop_chrome.dart';
import '../widgets/desktop_prompt_surface.dart';
import 'coding_memory_connection.dart';
import 'coding_memory_library.dart';

/// The collection's owner library; it does not send chat or terminal input.
class CodingMemoryView extends StatefulWidget {
  const CodingMemoryView({super.key, required this.library});
  final CodingMemoryLibrary library;
  @override
  State<CodingMemoryView> createState() => _CodingMemoryViewState();
}

class _CodingMemoryViewState extends State<CodingMemoryView> {
  String section = 'How you work';
  CodingMemoryLibrary get library => widget.library;

  @override
  void didUpdateWidget(CodingMemoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.library != library) section = 'How you work';
  }

  Future<void> _open({String? id, Map<String, dynamic>? command}) async {
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MemoryDialog(library: library, id: id, command: command),
    );
    if (mounted && library.valid) await library.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      if (library.available == false) return const SizedBox.shrink();
      return DesktopChrome(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your coding memory',
              style: AppType.title(color: AppPalette.textPrimary),
            ),
            const SizedBox(height: 8),
            _text(
              'Useful things learned as you work. Read the evidence, correct a detail, or let something go.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in [
                  'How you work',
                  'Project knowledge',
                  'Learning',
                ])
                  ChoiceChip(
                    label: Text(name),
                    selected: section == name,
                    onSelected: library.busy || !library.valid
                        ? null
                        : (_) {
                            setState(() => section = name);
                            unawaited(
                              library.refresh(
                                filter: name == 'Project knowledge'
                                    ? 'project'
                                    : 'personal',
                              ),
                            );
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (library.error != null) _text(library.error!),
            if (library.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (library.available == true && library.valid)
              if (section == 'Learning')
                _learning()
              else ...[
                if (library.items.isEmpty &&
                    !library.busy &&
                    library.error == null)
                  _text(
                    section == 'How you work'
                        ? 'A place for your coding preferences. Your companion can learn from new, included sessions while learning is on.'
                        : 'Project decisions and findings stay with their project. No project memories are available yet.',
                  ),
                for (final item in library.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppPalette.cardBg,
                        border: Border.all(color: AppPalette.divider),
                        borderRadius: BorderRadius.circular(
                          AppDesktop.rowRadius,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(
                            '${_stateLabel(item['state'])} · ${_scopeLabel(item)}',
                            small: true,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['claim'] as String,
                            style: AppType.body(
                              color: AppPalette.textPrimary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: library.busy
                                ? null
                                : () => _open(id: item['id'] as String),
                            child: const Text('Read memory'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (library.nextCursor != null)
                  TextButton(
                    onPressed: library.busy
                        ? null
                        : () => library.refresh(more: true),
                    child: const Text('Show more'),
                  ),
              ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: library.busy || !library.valid
                  ? null
                  : () => library.refresh(),
              child: const Text('Refresh coding memory'),
            ),
            const SizedBox(height: 28),
          ],
        ),
      );
    },
  );

  Widget _learning() {
    final status = library.status!;
    final runtime = memoryMap(status['runtime']);
    final learning = memoryMap(runtime['learning']);
    final queue = memoryMap(status['queue']);
    final jobs = memoryMap(queue['jobs']);
    final pending = [
      'open',
      'queued',
      'reviewing',
      'waiting_for_model',
      'source_incomplete',
      'budget_deferred',
      'failed',
    ].fold<int>(0, (sum, key) => sum + ((jobs[key] as num?)?.toInt() ?? 0));
    final gaps =
        (memoryMap(queue['retention'])['expiredEpisodes'] as num?)?.toInt() ??
        0;
    final state = runtime['state'] == 'off'
        ? 'Your companion is paused. These choices take effect when it resumes.'
        : !library.learn
        ? 'Learning is paused. Your existing memories are still here.'
        : learning['state'] == 'waiting_for_model'
        ? 'Waiting for the model selected in your companion’s terminal. Your model choice stays in control.'
        : runtime['state'] != 'ready'
        ? 'Waiting for your companion’s memory service to be ready.'
        : 'Learning from new, included coding sessions when your agents are quiet.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(state),
        const SizedBox(height: 12),
        _preference(
          'Learn from coding sessions',
          library.learn,
          'Form new memories from included work. Pausing keeps existing memories.',
          'learn',
        ),
        _preference(
          'Recall useful memories',
          library.recall,
          'Make relevant memories available to supported agents. Turning this off does not remove context already sent.',
          'recall',
        ),
        const SizedBox(height: 12),
        _text(
          '$pending ${pending == 1 ? 'session segment is' : 'session segments are'} waiting to be reviewed.',
          small: true,
        ),
        if (gaps > 0)
          _text(
            '$gaps ${gaps == 1 ? 'segment expired' : 'segments expired'} before learning finished. Those gaps are not counted as learned.',
            small: true,
          ),
        const SizedBox(height: 12),
        _text(
          'Memories are kept on this computer and separated by account and project. Switching the companion’s character keeps the same collection memory.',
          small: true,
        ),
      ],
    );
  }

  Widget _preference(String title, bool value, String detail, String key) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.body(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _text(detail, small: true),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: title,
              child: Switch(
                value: value,
                onChanged: library.busy
                    ? null
                    : (next) => _open(
                        command: {
                          'kind': 'configure',
                          'expected': {
                            'learn': library.learn,
                            'recall': library.recall,
                          },
                          'preferences': {
                            'learn': library.learn,
                            'recall': library.recall,
                            key: next,
                          },
                        },
                      ),
              ),
            ),
          ],
        ),
      );
}

Widget _text(String value, {bool small = false}) => Text(
  value,
  style: small
      ? AppType.caption(color: AppPalette.textSecondary, height: 1.5)
      : AppType.body(color: AppPalette.textSecondary, height: 1.5),
);

String _stateLabel(Object? state) => switch (state) {
  'active' => 'Saved',
  'tentative' => 'Possible memory',
  'needs_verification' => 'Needs review',
  'superseded' => 'Replaced',
  'archived' => 'Archived',
  _ => 'Memory',
};

String _scopeLabel(Map<String, dynamic> item) {
  final scope = memoryMap(item['scope']);
  return scope['taskId'] != null
      ? 'This task'
      : scope['branchId'] != null
      ? 'This branch'
      : scope['projectId'] != null
      ? 'This project'
      : 'Across your coding projects';
}

String _label(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]!.toLowerCase()}',
    )
    .replaceAll('_', ' ');

String _date(BuildContext context, Object? millis) {
  if (millis is! num) return 'Date unavailable';
  final date = DateTime.fromMillisecondsSinceEpoch(millis.toInt()).toLocal();
  return MaterialLocalizations.of(context).formatMediumDate(date);
}

// A structured field is rendered as ordinary text; no remembered content is
// evaluated, linked, interpreted as Markdown or inserted into a terminal.
Widget _fields(Object? value, {String? label}) {
  final children = <Widget>[];
  if (label != null) {
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          label,
          style: AppType.body(
            color: AppPalette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final v = entry.value;
      if (v != null &&
          v != '' &&
          !(v is List && v.isEmpty) &&
          !(v is Map && v.isEmpty)) {
        children.add(_fields(entry.value, label: _label('${entry.key}')));
      }
    }
  } else if (value is List) {
    for (final entry in value) {
      children.add(_fields(entry));
    }
  } else if (value != null) {
    children.add(
      SelectableText(
        '$value',
        style: AppType.body(color: AppPalette.textPrimary, height: 1.5),
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog({required this.library, this.id, this.command});
  final CodingMemoryLibrary library;
  final String? id;
  final Map<String, dynamic>? command;
  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  final _claim = TextEditingController(),
      _reason = TextEditingController(),
      _action = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _cancel = FocusNode();
  Map<String, dynamic>? detail;
  CodingMemoryPreview? preview;
  String? error;
  bool refreshedWhileEditing = false;
  bool busy = false, editing = false;
  bool _reloadNeeded = false, _closing = false;
  late int _seenChanges;
  CodingMemoryLibrary get library => widget.library;
  Map<String, dynamic> get record => memoryMap(detail?['record']);
  @override
  void initState() {
    super.initState();
    _seenChanges = library.changes;
    library.addListener(_changed);
    if (widget.id != null) {
      unawaited(_load());
    } else {
      unawaited(_preview(widget.command!));
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!library.valid) {
      detail = null;
      preview = null;
      _claim.clear();
      _reason.clear();
      _action.clear();
      error = codingMemoryError(const CodingMemoryFailure('OWNER_CHANGED'));
    } else if (_seenChanges != library.changes) {
      _seenChanges = library.changes;
      detail = null;
      preview = null;
      _reloadNeeded = widget.id != null;
    }
    setState(() {});
    if (_reloadNeeded && !busy && !_closing) {
      _reloadNeeded = false;
      unawaited(_load());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || !library.valid) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        error = codingMemoryError(failure);
        if (failure is CodingMemoryFailure &&
            [
              'NOT_FOUND',
              'OWNER_CHANGED',
              'PERSON_ONLY',
            ].contains(failure.code)) {
          detail = null;
          preview = null;
          _claim.clear();
          _reason.clear();
          _action.clear();
        }
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (_reloadNeeded && library.valid && !_closing) {
          _reloadNeeded = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _load() => _run(() async {
    final snapshot = library.changes;
    final result = await library.detail(widget.id!);
    if (!mounted || !library.valid || snapshot != library.changes) return;
    detail = result;
    refreshedWhileEditing = editing;
    if (!editing) {
      _claim.text = record['claim'] as String;
      _reason.text = record['rationale'] as String? ?? '';
      _action.text = record['futureAction'] as String;
    }
    preview = null;
  });
  Future<void> _preview(Map<String, dynamic> command) => _run(() async {
    final result = await library.preview(command);
    if (!mounted || !library.valid) return;
    preview = result;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cancel.requestFocus();
    });
  });

  Future<void> _refreshSettings() async {
    await library.refresh();
    if (!mounted || !library.valid || library.error != null) return;
    final original = widget.command!;
    final expected = memoryMap(original['expected']);
    final wanted = memoryMap(original['preferences']);
    final current = {'learn': library.learn, 'recall': library.recall};
    await _preview({
      'kind': 'configure',
      'expected': current,
      'preferences': {
        ...current,
        for (final key in ['learn', 'recall'])
          if (wanted[key] != expected[key]) key: wanted[key],
      },
    });
  }

  Map<String, dynamic> _correction() => {
    'kind': 'correct',
    'id': record['id'],
    'revision': record['revision'],
    'fields': {
      'claim': _claim.text.trim(),
      'rationale': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      'futureAction': _action.text.trim(),
      for (final key in [
        'applicability',
        'exceptions',
        'retrievalCues',
        'validity',
        'details',
      ])
        if (record.containsKey(key)) key: record[key],
    },
  };
  Future<void> _apply() => _run(() async {
    final applying = preview!;
    preview = null; // Spend once even if the reply is lost; never resend automatically.
    await library.apply(applying);
    if (mounted) {
      _closing = true;
      Navigator.of(context).pop();
    }
  });
  void _close() {
    if (!busy) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final command = memoryMap(preview?.data['command']);
    final kind = command['kind'];
    final title = !library.valid
        ? 'Memory unavailable'
        : preview != null
        ? switch (kind) {
            'forget' => 'Forget this memory?',
            'configure' => 'Update memory settings?',
            _ => 'Review your correction',
          }
        : editing
        ? 'Correct memory'
        : widget.id == null
        ? 'Memory settings'
        : 'Your coding memory';
    final canEdit =
        record['assertionType'] != 'verified_finding' &&
        memoryMap(memoryMap(record['details'])['experiment'])['runs'] == null;
    return PopScope(
      canPop: !busy,
      child: DesktopPromptSurface(
        width: 620,
        body: DesktopPromptScrollBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopDialogHeader(
                title: title,
                padding: EdgeInsets.zero,
                onClose: busy ? null : _close,
              ),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (library.valid)
                if (preview != null)
                  _previewBody(command)
                else if (detail != null)
                  editing ? _editor() : _detail(context),
            ],
          ),
        ),
        footer: error == null ? null : DesktopPromptMessage(error!),
        actions: [
          TextButton(
            focusNode: _cancel,
            autofocus: true,
            onPressed: busy ? null : _close,
            child: Text(preview == null ? 'Close' : 'Cancel'),
          ),
          if (library.valid && !busy)
            if (preview != null) ...[
              TextButton(
                onPressed: () => setState(() => preview = null),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: _apply,
                style: kind == 'forget'
                    ? FilledButton.styleFrom(
                        backgroundColor: AppPalette.dangerFill,
                        foregroundColor: Colors.white,
                      )
                    : null,
                child: Text(
                  kind == 'forget'
                      ? 'Forget memory'
                      : kind == 'configure'
                      ? 'Apply settings'
                      : 'Save correction',
                ),
              ),
            ] else if (detail != null && editing) ...[
              TextButton(
                onPressed: _load,
                child: const Text('Refresh current version'),
              ),
              FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    unawaited(_preview(_correction()));
                  }
                },
                child: const Text('Review correction'),
              ),
            ] else if (detail != null) ...[
              TextButton(
                onPressed: () => _preview({
                  'kind': 'forget',
                  'id': record['id'],
                  'revision': record['revision'],
                }),
                child: const Text('Forget…'),
              ),
              if (canEdit)
                FilledButton(
                  onPressed: () => setState(() => editing = true),
                  child: const Text('Correct memory'),
                ),
            ] else if (widget.command != null)
              TextButton(
                onPressed: _refreshSettings,
                child: const Text('Refresh and review settings'),
              )
            else
              TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context) {
    final sources = [
      for (final value in detail!['sources'] as List) memoryMap(value),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          '${_stateLabel(record['state'])} · ${_scopeLabel(record)}',
          small: true,
        ),
        _fields(record['claim'], label: 'What is remembered'),
        if (record['rationale'] != null)
          _fields(record['rationale'], label: 'Why it matters'),
        _fields(record['futureAction'], label: 'How it can help'),
        _constraints(record),
        const SizedBox(height: 20),
        Text(
          'Retained evidence',
          style: AppType.heading(color: AppPalette.textPrimary),
        ),
        const SizedBox(height: 8),
        _text(
          record['evidenceClass'] == 'inferred'
              ? 'This was inferred, not directly stated. Review it before relying on it.'
              : 'These are the retained source excerpts, not the surrounding conversation.',
          small: true,
        ),
        for (final value in record['evidence'] as List)
          Builder(
            builder: (_) {
              final evidence = memoryMap(value);
              final source = sources
                  .where((s) => s['id'] == evidence['sourceEventId'])
                  .firstOrNull;
              final date = source?['observedAt'];
              final observed = date is num
                  ? MaterialLocalizations.of(context).formatMediumDate(
                      DateTime.fromMillisecondsSinceEpoch(date.toInt())
                          .toLocal(),
                    )
                  : 'Date unavailable';
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(
                      '${source?['role'] == 'user' ? 'You' : _label('${source?['role'] ?? 'source'}')} · ${source?['engine'] ?? ''} · $observed',
                      small: true,
                    ),
                    _fields(evidence['quote']),
                    if (evidence['verification'] != null)
                      _fields(
                        evidence['verification'],
                        label: 'Verification and limits',
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _constraints(Map<String, dynamic> fields) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (memoryMap(fields['scope'])['projectId'] != null)
        _fields(
          memoryMap(fields['scope'])..remove('profileId'),
          label: 'Project scope',
        ),
      if (memoryMap(fields['applicability']).isNotEmpty)
        _fields(fields['applicability'], label: 'Applies when'),
      if ((fields['exceptions'] as List?)?.isNotEmpty == true)
        _fields(fields['exceptions'], label: 'Exceptions'),
      if (fields['details'] != null)
        _fields(fields['details'], label: 'Other remembered details'),
      if ((fields['retrievalCues'] as List?)?.isNotEmpty == true)
        _fields(
          (fields['retrievalCues'] as List).join(', '),
          label: 'Recall cues',
        ),
      if (fields['validity'] != null)
        Builder(
          builder: (context) {
            final validity = memoryMap(fields['validity']);
            return _fields({
              if (validity['validFrom'] != null)
                'From': _date(context, validity['validFrom']),
              if (validity['validUntil'] != null)
                'Until': _date(context, validity['validUntil']),
              if ((validity['recheckWhen'] as List?)?.isNotEmpty == true)
                'Recheck when': validity['recheckWhen'],
            });
          },
        ),
    ],
  );

  Widget _editor() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (refreshedWhileEditing) ...[
          _fields(record['claim'], label: 'Current saved version'),
          const SizedBox(height: 12),
          _text(
            'Your draft is preserved below. Compare it with the current version before saving.',
          ),
          const SizedBox(height: 16),
        ],
        _text(
          'Your correction becomes a direct statement from you. Review the scope and details below; saving confirms them too.',
        ),
        const SizedBox(height: 16),
        for (final field in [
          (_claim, 'What should be remembered', true),
          (_reason, 'Why it matters (optional)', false),
          (_action, 'How it should help next time', true),
        ]) ...[
          TextFormField(
            controller: field.$1,
            enabled: !busy,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: InputDecoration(labelText: field.$2),
            validator: (value) => field.$3 && (value?.trim().isEmpty ?? true)
                ? 'Enter a short description.'
                : null,
          ),
          const SizedBox(height: 12),
        ],
        _text(
          'Scope: ${_scopeLabel(record)}. Scope and conditions are preserved.',
          small: true,
        ),
        _constraints(record),
      ],
    ),
  );

  Widget _previewBody(Map<String, dynamic> command) {
    final effects = memoryMap(preview!.data['effects']);
    if (command['kind'] == 'forget') {
      final memories = (effects['deletedIds'] as List).length;
      final topics = (effects['deletedTopicIds'] as List).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fields(record['claim']),
          const SizedBox(height: 16),
          _text(
            'This removes $memories ${memories == 1 ? 'memory' : 'memories'}, including dependent memories, and $topics ${topics == 1 ? 'notebook page' : 'notebook pages'} from this account on this computer.',
          ),
          const SizedBox(height: 12),
          _text(
            'Original conversations and context already sent to an agent are not erased. Start a fresh agent conversation if you need to leave that earlier context behind.',
          ),
        ],
      );
    }
    if (command['kind'] == 'configure') {
      final preferences = memoryMap(command['preferences']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text('Learning: ${preferences['learn'] == true ? 'On' : 'Paused'}'),
          _text('Recall: ${preferences['recall'] == true ? 'On' : 'Off'}'),
          const SizedBox(height: 12),
          _text(
            'Existing memories stay saved. Your companion must be running to learn or recall. Context already delivered remains in earlier agent conversations.',
          ),
        ],
      );
    }
    final fields = memoryMap(command['fields']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          'Save this as your statement for ${_scopeLabel(record).toLowerCase()}?',
        ),
        _fields(fields['claim'], label: 'What will be remembered'),
        if (fields['rationale'] != null)
          _fields(fields['rationale'], label: 'Why it matters'),
        _fields(fields['futureAction'], label: 'How it should help'),
        _constraints({...fields, 'scope': record['scope']}),
      ],
    );
  }

  @override
  void dispose() {
    library.removeListener(_changed);
    _claim.dispose();
    _reason.dispose();
    _action.dispose();
    _cancel.dispose();
    super.dispose();
  }
}
