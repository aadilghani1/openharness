import 'dart:async';

import 'package:flutter/material.dart';

import '../daemons/daemon_brain.dart';
import '../daemons/illustrated_art.dart';
import '../daemons/individuals.dart';
import '../daemons/zoo.dart';
import '../shared/theme/app_type.dart';
import '../theme/app_theme.dart';
import '../widgets/daemon_illustration.dart';
import 'companion_story.dart';

/// A friendly front end for the existing, on-demand autonomous/pair DSH.
/// Nothing starts until the person sends words. The engine's full conversation
/// and permission prompts remain available through [onOpenConversation].
class CompanionChat extends StatefulWidget {
  const CompanionChat({
    super.key,
    required this.brain,
    required this.daemon,
    this.traits,
    this.onOpenConversation,
    this.canOpenConversation,
    this.onOpenControls,
    this.focusRequest = 0,
    this.preview = false,
  });
  final DaemonBrain brain;
  final ZooDaemon? daemon;
  final DaemonTraits? traits;
  final VoidCallback? onOpenConversation, onOpenControls;
  final bool Function()? canOpenConversation;
  final int focusRequest;
  final bool preview;

  @override
  State<CompanionChat> createState() => _CompanionChatState();
}

class _CompanionChatState extends State<CompanionChat> {
  final _input = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Companion conversation');
  final _scroll = ScrollController();
  int _length = 0;
  Timer? _retryTicker;

  @override
  void initState() {
    super.initState();
    widget.brain.addListener(_changed);
    if (widget.focusRequest > 0) _requestFocus();
  }

  @override
  void didUpdateWidget(CompanionChat old) {
    super.didUpdateWidget(old);
    if (old.brain != widget.brain) {
      old.brain.removeListener(_changed);
      widget.brain.addListener(_changed);
    }
    if (old.daemon?.uid != widget.daemon?.uid) _input.clear();
    if (old.focusRequest != widget.focusRequest) _requestFocus();
  }

  void _requestFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _focus.requestFocus();
  });

  void _changed() {
    if (!mounted) return;
    if (widget.brain.talkWait != null) {
      _retryTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || widget.brain.talkWait == null) {
          _retryTicker?.cancel();
          _retryTicker = null;
        }
        if (mounted) setState(() {});
      });
    }
    final nearBottom =
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.offset < 80;
    final grew = widget.brain.talk.length != _length;
    _length = widget.brain.talk.length;
    setState(() {});
    if (grew && nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  bool get _available =>
      !widget.preview &&
      widget.daemon != null &&
      widget.brain.paired &&
      widget.brain.state?.pair == widget.daemon!.id;
  bool get _canSend =>
      _available &&
      widget.brain.talkWait == null &&
      widget.brain.talkPhase != DaemonTalkPhase.waking;

  void _send([String? suggestion]) {
    if (!_canSend) return;
    final text = suggestion ?? _input.text;
    if (widget.brain.talkTo(text)) _input.clear();
    _focus.requestFocus();
  }

  TextStyle _text([double size = 14, Color? color]) => TextStyle(
    fontFamily: AppType.sansFamily,
    fontFamilyFallback: AppType.sansFallback,
    fontSize: size,
    height: 1.5,
    color: color ?? AppColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final daemon = widget.daemon;
    final name = daemon == null ? 'your companion' : companionName(daemon);
    final accent = CompanionStory.of(daemon?.id ?? 'tim').accent;
    final brain = widget.brain;
    final status = brain.talkNeedsSetup
        ? 'Your model may need first-time setup. Open the full conversation to continue.'
        : brain.talkWait != null
        ? 'You can send another message in ${(brain.talkWait!.inMilliseconds / 1000).ceil()} seconds.'
        : switch (brain.talkPhase) {
            DaemonTalkPhase.waking => 'Waking $name…',
            DaemonTalkPhase.started || DaemonTalkPhase.resumed =>
              '$name is getting settled. The conversation is starting…',
            DaemonTalkPhase.sent => '$name is listening…',
            DaemonTalkPhase.failed =>
              brain.talkError ?? 'Your message could not be sent.',
            _ => null,
          };
    return Material(
      key: const ValueKey('companion-chat'),
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 18, 18),
            child: Row(
              children: [
                if (daemon != null) ...[
                  DaemonIllustration(
                    art: IllustratedArt.daemon(
                      daemon.id,
                      version: daemon.version,
                      traits: widget.traits,
                    ),
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A moment with ${daemon == null ? 'a friend' : name}',
                        style: _text(16).copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _available
                            ? 'Your companion, here with you'
                            : 'A little company for your day',
                        style: _text(12, AppColors.textSoft),
                      ),
                    ],
                  ),
                ),
                if (widget.onOpenConversation != null &&
                    (widget.canOpenConversation?.call() ?? true))
                  IconButton(
                    key: const ValueKey('companion-conversation'),
                    tooltip: 'Open full conversation and permissions',
                    onPressed: widget.onOpenConversation,
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: AppColors.textSoft,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(24),
              children: [
                if (brain.talk.isEmpty) ...[
                  const SizedBox(height: 28),
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 28,
                    color: accent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Every friendship starts\nwith a hello.',
                    textAlign: TextAlign.center,
                    style: _text(23)
                        .copyWith(fontFamily: 'Georgia', height: 1.3),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Share an idea, ask about your work, or get to know $name. '
                    'This is a conversation you can come back to.',
                    textAlign: TextAlign.center,
                    style: _text(14, AppColors.textSoft),
                  ),
                  const SizedBox(height: 26),
                  for (final prompt in [
                    'Tell me your story',
                    'What are we working on?',
                    'What have we learned together?',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _canSend ? () => _send(prompt) : null,
                        child: Text(
                          prompt,
                          style: _text(
                            13,
                            _canSend ? AppColors.text : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                ],
                for (final entry in brain.talk)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.you ? 'You' : name,
                          style: _text(
                            12,
                            AppColors.textSoft,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: entry.you
                                ? AppColors.surface
                                : accent.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SelectableText(entry.text, style: _text()),
                        ),
                      ],
                    ),
                  ),
                if (status != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      key: const ValueKey('companion-chat-status'),
                      style: _text(
                        13,
                        brain.talkPhase == DaemonTalkPhase.failed
                            ? AppColors.danger
                            : AppColors.textSoft,
                      ),
                    ),
                  ),
                if (brain.talkNeedsSetup &&
                    widget.onOpenConversation != null &&
                    (widget.canOpenConversation?.call() ?? true))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('companion-chat-setup'),
                      onPressed: widget.onOpenConversation,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open full conversation'),
                    ),
                  ),
                if (!_available) ...[
                  const SizedBox(height: 20),
                  Text(
                    widget.preview
                        ? 'Gallery previews are for exploring. Chat is available with your paired companion.'
                        : daemon == null
                        ? 'Hatch your first companion to begin.'
                        : 'Chat connects through the companion on this computer. '
                              'If this is your first visit, open companion settings to get started.',
                    style: _text(13, AppColors.textSoft),
                  ),
                  if (widget.onOpenControls != null)
                    TextButton(
                      onPressed: widget.onOpenControls,
                      child: const Text('Companion settings'),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.borderStrong),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 5, 5, 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('companion-chat-input'),
                          controller: _input,
                          focusNode: _focus,
                          enabled: _available,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          style: _text(),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: 'Say something to $name…',
                            hintStyle: _text(14, AppColors.textSoft),
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('companion-chat-send'),
                        tooltip: 'Send message',
                        onPressed: _canSend ? _send : null,
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          color: _canSend ? AppColors.text : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  brain.talkCost ?? 'Messages use your connected model and count toward your model usage. The full conversation stays in your companion’s harness.',
                  key: const ValueKey('companion-chat-cost'),
                  style: _text(11, AppColors.textSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.brain.removeListener(_changed);
    _retryTicker?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
