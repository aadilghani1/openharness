import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'desktop_chrome.dart';
import 'box_chrome.dart' show ReadlineKeys;
import 'swarm_switcher.dart';
import 'swarm_search_input.dart';

/// A desktop command palette over the existing search and activation pipeline.
/// Category buttons edit the same query as keyboard prefixes; no second index.
class DesktopSearchPanel extends StatelessWidget {
  const DesktopSearchPanel({
    super.key,
    required this.search,
    required this.editing,
    required this.focusNode,
    required this.onChoose,
    required this.onClose,
    required this.onRefocus,
    required this.previewBuilder,
  });

  final SwarmSearchController search;
  final TextEditingController editing;
  final FocusNode focusNode;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose, onRefocus;
  final Widget Function() previewBuilder;

  static const categories = [
    ('All', ''),
    ('Projects', '#'),
    ('Machines', '@'),
    ('Models', ':'),
    ('Store', '*'),
    ('Commands', '>'),
  ];

  String get _prefix => search.isProjectMode
      ? '#'
      : search.isMachineMode
      ? '@'
      : search.isModelMode
      ? ':'
      : search.isStoreMode
      ? '*'
      : search.isCommandMode
      ? '>'
      : '';

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DesktopChrome(
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          key: const ValueKey('swarm-search-results'),
          color: DesktopChrome.surface,
          elevation: 24,
          shadowColor: Colors.black.withValues(alpha: .4),
          shape: DesktopChrome.shape(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: DesktopChrome.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ReadlineKeys(
                        controller: editing,
                        onChanged: search.setQuery,
                        child: SwarmSearchInput(
                          inputKey: const ValueKey('swarm-search-input'),
                          controller: editing,
                          focusNode: focusNode,
                          search: search,
                          onClose: onClose,
                          onChanged: search.setQuery,
                          onOpen: onRefocus,
                          hintText: search.hint,
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: search,
                      builder: (context, _) => IconButton(
                        key: const ValueKey('search-toggle-preview'),
                        tooltip: search.previewVisible
                            ? 'Hide preview'
                            : 'Show preview',
                        isSelected: search.previewVisible,
                        onPressed: search.supportsPreview
                            ? () {
                                search.togglePreview();
                                onRefocus();
                              }
                            : null,
                        icon: const Icon(
                          Icons.vertical_split_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close search',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: DesktopChrome.rim),
              ListenableBuilder(
                listenable: search,
                builder: (context, _) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      for (final (label, prefix) in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: DesktopPill(
                            key: ValueKey('search-category-$label'),
                            label: label,
                            selected: _prefix == prefix,
                            tooltip: prefix.isEmpty
                                ? 'Search everything'
                                : '$label · $prefix',
                            onPressed: () {
                              final words = search.wordsQuery;
                              search.setQuery(
                                prefix.isEmpty
                                    ? words
                                    : '$prefix $words'.trimRight(),
                              );
                              onRefocus();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: ListenableBuilder(
                  listenable: search,
                  builder: (context, _) => SwarmSearchResults(
                    search: search,
                    onChoose: onChoose,
                    onRefocus: onRefocus,
                    fitRows: true,
                    // The category pills already explain the empty search.
                    // Give results the full width until there is a preview.
                    showPreview: !search.showsTypeHints,
                    sideBySideMinWidth: 840,
                    previewBuilder: previewBuilder,
                  ),
                ),
              ),
              Divider(height: 1, color: DesktopChrome.rim),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                child: Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  children: [
                    _hint(context, 'picker.next', 'Browse'),
                    _hint(context, 'picker.accept', 'Open'),
                    _hint(context, 'picker.cancel', 'Close'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String command, String label) {
    final key = effectiveCommandHint(
      context,
      command,
      contextKind: KeymapContext.picker,
    );
    if (key == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(key, style: grid.AppType.monoMeta(color: DesktopChrome.muted)),
        const SizedBox(width: 7),
        Text(
          label,
          style: DesktopChrome.text(size: 12, color: DesktopChrome.muted),
        ),
      ],
    );
  }
}
