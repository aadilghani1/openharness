import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;

/// Experimental desktop presentation around the terminal. The same controllers
/// and keyboard actions still own creation, search, and resource management.
class DesktopChrome extends InheritedWidget {
  const DesktopChrome({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopChrome>() != null;

  static Color get foreground => grid.AppPalette.textPrimary;
  static Color get muted => grid.AppPalette.textSecondary;
  static Color get surface => grid.AppPalette.cardBg;
  static Color get rim => foreground.withValues(alpha: .13);
  static Color get field =>
      Color.alphaBlend(foreground.withValues(alpha: .035), surface);
  static TextStyle text({
    Color? color,
    double size = 14,
    bool medium = false,
  }) => grid.AppType.body(
    color: color ?? foreground,
    fontWeight: medium ? FontWeight.w500 : FontWeight.w400,
    height: 1.45,
  ).copyWith(fontSize: size);

  static ShapeBorder shape({double radius = 18}) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: rim),
  );

  @override
  bool updateShouldNotify(DesktopChrome oldWidget) => false;
}

/// The Store's quiet capsule treatment, with normal focus and disabled states.
class DesktopPill extends StatelessWidget {
  const DesktopPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.menu = false,
    this.selected,
    this.tooltip,
    this.monospace = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool menu, monospace;
  final bool? selected;
  final String? tooltip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = DesktopChrome.foreground;
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        disabledForegroundColor: ink.withValues(alpha: .38),
        backgroundColor: ink.withValues(alpha: selected == true ? .13 : .055),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: StadiumBorder(side: BorderSide(color: DesktopChrome.rim)),
        textStyle: DesktopChrome.text(size: 13),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 7)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monospace ? grid.AppType.mono() : null,
              semanticsLabel: semanticLabel,
            ),
          ),
          if (menu) ...[
            const SizedBox(width: 7),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ],
        ],
      ),
    );
    final control = Semantics(selected: selected, child: button);
    return tooltip == null
        ? control
        : Tooltip(message: tooltip!, child: control);
  }
}
