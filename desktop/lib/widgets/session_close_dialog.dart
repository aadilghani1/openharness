import 'package:flutter/material.dart';

import '../core/models.dart';
import '../shortcuts/app_keymap.dart';
import '../shared/theme/app_theme.dart' as grid;
import 'desktop_chrome.dart';
import 'desktop_prompt_surface.dart';
import 'terminal_prompt.dart';

/// A close decision names its consequence. Cancel is the default, never Stop.
Future<String?> showSessionCloseDialog(
  BuildContext context,
  Agent agent,
  String activity, {
  AppKeymap? keymap,
  String? error,
}) => showTerminalPrompt<String>(
  context,
  keymap: keymap,
  builder: (_) =>
      _SessionClosePrompt(agent: agent, activity: activity, error: error),
);

class _SessionClosePrompt extends StatefulWidget {
  const _SessionClosePrompt({
    required this.agent,
    required this.activity,
    this.error,
  });
  final Agent agent;
  final String activity;
  final String? error;
  @override
  State<_SessionClosePrompt> createState() => _SessionClosePromptState();
}

class _SessionClosePromptState extends State<_SessionClosePrompt> {
  final _cancel = FocusNode(debugLabel: 'Cancel session close');
  final _keys = FocusNode(debugLabel: 'Session close');
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cancel.requestFocus();
    });
  }

  @override
  void dispose() {
    _cancel.dispose();
    _keys.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _choose([String? choice]) => Navigator.pop(context, choice);

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final hasConversation =
        widget.agent.sessionId?.isNotEmpty == true &&
        widget.agent.resumeMode != 'fresh' &&
        widget.agent.resumeMode != 'shell';
    final description = switch (widget.activity) {
      'working' => 'This session is still working. Stop now, or let it finish in the background and close afterward.',
      'needs_input' => 'This session is waiting for input. If you close after finishing, it stays available in Harness Monitor until you answer and its work finishes.',
      'draft' => 'There is unsent text in this session. Stop now saves a terminal snapshot without sending it. Your saved conversation is kept.',
      'in_use' => 'This session is open in another window or device. Stopping it ends the running session there too. Switching tabs keeps it running.',
      _ => 'Harness could not confirm that this session is idle. You can stop it now, or keep it running until its work finishes.',
    };
    return TerminalPromptKeys(
      focusNode: _keys,
      cancel: _choose,
      child: DesktopPromptSurface(
        body: DesktopPromptScrollBody(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.error == null
                    ? 'Close session'
                    : 'Could not close session',
                style: DesktopChrome.heading(),
              ),
              const SizedBox(height: DesktopChrome.groupGap),
              Text(
                widget.agent.displayName,
                style: DesktopChrome.text(size: 14, medium: true),
              ),
              const SizedBox(height: DesktopChrome.groupGap),
              Text(
                widget.error ?? description,
                style: DesktopChrome.text(size: 13),
              ),
              if (widget.error == null) ...[
                const SizedBox(height: 8),
                Text(
                  hasConversation
                      ? 'Saved history stays on disk. Reopen it from Open Harness or Harness Monitor.'
                      : 'This session has not saved a conversation yet. A terminal snapshot is kept; reopening starts a new conversation.',
                  style: DesktopChrome.text(
                    size: 13,
                    color: DesktopChrome.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            focusNode: _cancel,
            onPressed: _choose,
            child: Text(widget.error == null ? 'Cancel' : 'OK'),
          ),
          if (widget.error == null) ...[
            FilledButton(
              key: const Key('session-close-now'),
              style: grid.dangerButtonStyle(),
              onPressed: () => _choose('now'),
              child: const Text('Stop now'),
            ),
            if (hasConversation)
              FilledButton(
                key: const Key('session-close-after'),
                onPressed: () => _choose('after_task'),
                child: const Text('Stop after finishing'),
              ),
          ],
        ],
      ),
    );
  }
}
