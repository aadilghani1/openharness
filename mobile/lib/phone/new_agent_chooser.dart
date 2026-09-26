import 'package:flutter/material.dart';


import 'fzf.dart';
import 'tty.dart';

/// One row of a [showNewAgentChooser] list.
class ChooserItem<T> {
  const ChooserItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.selected = false,
    this.enabled = true,
    this.warn = false,
  });

  final T value;
  final String title;

  /// Under the title, in the faint face — a folder's machine and path, an engine's "not installed".
  final String? subtitle;

  final IconData? icon;

  /// Drawn in place of [icon] — an engine's own mark.
  final Widget? leading;

  final bool selected;
  final bool enabled;

  /// Drawn in the warning colour: a choice that lets the agent do more than it should by default.
  final bool warn;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return title.toLowerCase().contains(needle) ||
        (subtitle?.toLowerCase().contains(needle) ?? false);
  }
}

/// A chooser for one of New's rows — fzf, the same list as Find: one-line rows over a `> ` prompt,
/// the likeliest answer next to it, the count and `esc` on the info line.
///
/// [items] sit nearest the prompt; [actions] (the Project chooser's clone, open folder, new folder)
/// above them, never filtered.
Future<T?> showNewAgentChooser<T>(
  BuildContext context, {
  required String hint,
  required List<ChooserItem<T>> items,
  List<ChooserItem<T>> actions = const [],
}) => Navigator.of(context, rootNavigator: true).push<T>(
  PageRouteBuilder<T>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (_, _, _) =>
        _Chooser<T>(hint: hint, items: items, actions: actions),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class _Chooser<T> extends StatefulWidget {
  const _Chooser({
    required this.hint,
    required this.items,
    required this.actions,
  });

  final String hint;
  final List<ChooserItem<T>> items;
  final List<ChooserItem<T>> actions;

  @override
  State<_Chooser<T>> createState() => _ChooserState<T>();
}

class _ChooserState<T> extends State<_Chooser<T>> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _choose(ChooserItem<T> item) {
    if (!item.enabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(item.value);
  }

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final query = _query.trim();
    final matches = [
      for (final item in widget.items)
        if (item.matches(query)) item,
    ];
    // Reversed: the first match sits on the prompt, the actions at the top of the screen.
    final rows = [...matches, ...widget.actions];
    final terms = query.isEmpty
        ? const <String>[]
        : query.split(RegExp(r'\s+'));
    return Scaffold(
      backgroundColor: tty.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 10),
                child: TtyText(widget.hint.toLowerCase(), color: tty.faint),
              ),
            ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final item = rows[index];
                  final action = index >= matches.length;
                  return FzfRow(
                    title: item.title,
                    detail: item.subtitle,
                    terms: action ? const [] : terms,
                    mark: item.selected ? '*' : (action ? '+' : null),
                    markColor: action ? tty.cyan : tty.green,
                    enabled: item.enabled,
                    trailingColor: item.warn ? tty.yellow : null,
                    trailing: item.warn ? 'risky' : null,
                    onTap: () => _choose(item),
                  );
                },
              ),
            ),
            FzfInfoLine(
              matched: matches.length,
              total: widget.items.length,
              actions: [
                (
                  label: 'esc',
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            FzfPrompt(
              controller: _controller,
              focus: _focus,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: () {
                final first = matches.where((item) => item.enabled).firstOrNull;
                if (first != null) _choose(first);
              },
            ),
          ],
        ),
      ),
    );
  }
}
