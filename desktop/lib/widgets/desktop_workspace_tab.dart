import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../shared/theme/app_icons.dart';
import '../shared/theme/app_theme.dart' as grid;
import 'box_chrome.dart';
import 'desktop_chrome.dart';

/// The Flutter counterpart of the AppKit tab: a name, a quiet activity mark,
/// and one trailing accessory. Hover and shortcut hints never move the name.
class DesktopWorkspaceTab extends StatefulWidget {
  const DesktopWorkspaceTab({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.showShortcuts,
    required this.onSelect,
    required this.onClose,
    this.shortcutHint,
    this.tooltip,
    this.activity,
    this.activityLabel,
    this.highlighted = false,
    this.onRename,
  });

  final String id, label;
  final bool selected, highlighted;
  final ValueListenable<bool> showShortcuts;
  final VoidCallback? onSelect, onClose;
  final VoidCallback? onRename;
  final String? shortcutHint, tooltip, activityLabel;
  final Widget? activity;

  static double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static double accessoryWidth(BuildContext context, String? hint) => math
      .max(
        28.0,
        hint == null
            ? 0.0
            : _measure(context, hint, DesktopChrome.metadata()) + 8,
      )
      .clamp(28.0, 72.0);

  static double labelWidth(BuildContext context, String label) =>
      _measure(context, label, DesktopChrome.control());

  static double widthOf(
    BuildContext context,
    String label, {
    String? shortcutHint,
    bool hasActivity = false,
  }) =>
      (labelWidth(context, label) +
              32 +
              accessoryWidth(context, shortcutHint) +
              (hasActivity ? 20 : 0))
          .clamp(116, 240);

  @override
  State<DesktopWorkspaceTab> createState() => _DesktopWorkspaceTabState();
}

class _DesktopWorkspaceTabState extends State<DesktopWorkspaceTab> {
  bool _hovered = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final enabled = widget.onSelect != null;
    final focusVisible = _focused || widget.highlighted;
    // Workspace palettes can stay dark beside light app surfaces. Match the
    // native tab bar's ink to its own surface, independent of terminal colors.
    final foreground = grid.AppTheme.palette.value.foreground;
    final muted = foreground.withValues(alpha: .65);
    final fill = widget.selected
        ? grid.AppPalette.swarmWelcome
        : _hovered
        ? foreground.withValues(alpha: .06)
        : Colors.transparent;
    final ink = enabled
        ? widget.selected || _hovered || focusVisible
              ? foreground
              : muted
        : foreground.withValues(alpha: .38);
    Widget tab = Padding(
      padding: const EdgeInsets.only(top: grid.AppDesktop.tabTopInset),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: DesktopTabBorder(
            side: focusVisible
                ? BorderSide(color: DesktopChrome.focusRing)
                : BorderSide.none,
          ),
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          selected: widget.selected,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: [widget.label, ?widget.activityLabel].join(', '),
                  onTap: widget.onSelect,
                  customSemanticsActions: {
                    if (widget.onClose != null)
                      const CustomSemanticsAction(label: 'Close tab'):
                          widget.onClose!,
                  },
                  child: FocusableActionDetector(
                    enabled: enabled,
                    onShowFocusHighlight: (value) =>
                        setState(() => _focused = value),
                    actions: {
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          widget.onSelect?.call();
                          return null;
                        },
                      ),
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onSelect,
                      onDoubleTap: widget.onRename,
                      child: SizedBox.expand(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ExcludeSemantics(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopChrome.control(color: ink),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.activity != null) ...[
                const SizedBox(width: 6),
                widget.activity!,
              ],
              const SizedBox(width: 4),
              SizedBox(
                width: DesktopWorkspaceTab.accessoryWidth(
                  context,
                  widget.shortcutHint,
                ),
                child: ValueListenableBuilder(
                  valueListenable: widget.showShortcuts,
                  builder: (context, showHints, _) {
                    if (showHints && widget.shortcutHint != null) {
                      return Center(
                        child: Text(
                          widget.shortcutHint!,
                          key: ValueKey('tab-shortcut:${widget.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopChrome.metadata(color: ink),
                        ),
                      );
                    }
                    return IgnorePointer(
                      ignoring: !_hovered,
                      child: ExcludeFocus(
                        excluding: !_hovered,
                        child: ExcludeSemantics(
                          excluding: !_hovered,
                          child: Opacity(
                            opacity: _hovered ? 1 : 0,
                            child: IconButton(
                              key: ValueKey('tab-close:${widget.id}'),
                              tooltip: 'Close tab',
                              onPressed: widget.onClose,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              style: IconButton.styleFrom(
                                foregroundColor: ink,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ).copyWith(animationDuration: Duration.zero),
                              icon: const Icon(AppIcons.close, size: 16),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
    if (widget.tooltip case final tooltip? when tooltip.isNotEmpty) {
      tab = Tooltip(message: tooltip, excludeFromSemantics: true, child: tab);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: widget.onSelect,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: tab,
      ),
    );
  }
}
