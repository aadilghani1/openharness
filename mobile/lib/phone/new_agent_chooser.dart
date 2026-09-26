import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

import 'phone_search_field.dart';
import 'sheet_list.dart';

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

/// A chooser for one of New Harness's rows — the desktop ⌘N box's chooser, as a sheet.
///
/// [actions] come first and are never filtered: the Project chooser's Clone Repository, Open
/// Folder and New Folder, which the desktop lists above its projects the same way. [items] follow,
/// narrowed by the field when there are enough of them to want it.
Future<T?> showNewAgentChooser<T>(
  BuildContext context, {
  required String hint,
  required List<ChooserItem<T>> items,
  List<ChooserItem<T>> actions = const [],
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  backgroundColor: AppPalette.panelBg,
  isScrollControlled: true,
  builder: (_) => _Chooser<T>(hint: hint, items: items, actions: actions),
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
  /// Fewer rows than this need no field: the answer is already on screen.
  static const _searchFrom = 7;

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
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(item.value);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final query = _query.trim();
    final matches = [
      for (final item in widget.items)
        if (item.matches(query)) item,
    ];
    final rows = [...widget.actions, ...matches];
    final searchable =
        widget.items.length + widget.actions.length >= _searchFrom;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kSheetInset,
                0,
                kSheetInset,
                10,
              ),
              child: PhoneSearchField(
                controller: _controller,
                focus: _focus,
                onBack: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.of(context).pop();
                },
                // Not autofocused: the likely answer is already on screen, where a keyboard
                // would bury it.
                autofocus: false,
                hintText: widget.hint,
                onChanged: (value) => setState(() => _query = value),
                onClear: () => setState(() {
                  _controller.clear();
                  _query = '';
                }),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                kSheetInset,
                0,
                kSheetInset,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final item = rows[index];
                final tint = !item.enabled
                    ? AppPalette.textFaint
                    : item.warn
                    ? AppPalette.warn
                    : item.selected
                    ? AppPalette.accentOnSurface
                    : AppPalette.textSecondary;
                return SheetRow(
                  first: index == 0,
                  last: index == rows.length - 1,
                  enabled: item.enabled,
                  leading: SheetTile(
                    child:
                        item.leading ??
                        Icon(
                          item.icon ?? LucideIcons.circle300,
                          size: 18,
                          color: tint,
                        ),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sheetRowTitleStyle(),
                  ),
                  subtitle: item.subtitle == null
                      ? null
                      : Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppPalette.textFaint,
                            fontSize: 12.5,
                          ),
                        ),
                  chevron: false,
                  selected: item.selected,
                  trailing: item.selected
                      ? Icon(
                          LucideIcons.check300,
                          size: 18,
                          color: AppPalette.accent,
                        )
                      : null,
                  onTap: () => _choose(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
