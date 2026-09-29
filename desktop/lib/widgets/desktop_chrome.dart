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
  static Color get accent => grid.AppPalette.accentOnSurface;
  static Color get selection => accent.withValues(alpha: .16);
  static Color get focusRing => accent.withValues(alpha: .75);
  static const dialogRadius = 16.0;
  static TextStyle text({
    Color? color,
    double size = 14,
    bool medium = false,
  }) => grid.AppType.body(
    color: color ?? foreground,
    fontWeight: medium ? FontWeight.w500 : FontWeight.w400,
    height: 1.45,
  ).copyWith(fontSize: size);

  static ShapeBorder shape({double radius = dialogRadius}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: rim),
      );

  @override
  bool updateShouldNotify(DesktopChrome oldWidget) => false;
}

/// Shared by creation, search, and their child choosers. A visible frame keeps
/// the modal distinct from the workspace without turning it into another page.
class DesktopDialogSurface extends StatelessWidget {
  const DesktopDialogSurface({
    super.key,
    required this.child,
    this.radius = DesktopChrome.dialogRadius,
    this.elevation = 16,
  });

  final Widget child;
  final double radius;
  final double elevation;

  @override
  Widget build(BuildContext context) => Material(
    color: DesktopChrome.surface,
    surfaceTintColor: Colors.transparent,
    elevation: elevation,
    shadowColor: Colors.black.withValues(alpha: .24),
    shape: DesktopChrome.shape(radius: radius),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class DesktopDialogBackdrop extends StatelessWidget {
  const DesktopDialogBackdrop({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .76 : .40,
        ),
      ),
    ),
  );
}

/// The Store's quiet capsule treatment, with normal focus and disabled states.
class DesktopPill extends StatelessWidget {
  const DesktopPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.menu = false,
    this.selected,
    this.tooltip,
    this.monospace = false,
    this.semanticLabel,
    this.semanticHint,
    this.focusNode,
    this.foregroundColor,
    this.compact = false,
    this.quiet = false,
    this.capsule = false,
    this.textSize = 13,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final bool menu, monospace;
  final bool? selected;
  final String? tooltip;
  final String? semanticLabel;
  final String? semanticHint;
  final FocusNode? focusNode;
  final Color? foregroundColor;
  final bool compact;
  final bool quiet, capsule;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final ink = foregroundColor ?? DesktopChrome.foreground;
    final button = TextButton(
      focusNode: focusNode,
      onPressed: onPressed,
      style:
          TextButton.styleFrom(
            foregroundColor: ink,
            disabledForegroundColor: ink.withValues(alpha: .38),
            backgroundColor: quiet
                ? Colors.transparent
                : ink.withValues(alpha: selected == true ? .13 : .055),
            minimumSize: Size(
              0,
              compact
                  ? 28
                  : capsule
                  ? 32
                  : 34,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: quiet
                  ? 6
                  : compact
                  ? 9
                  : 11,
              vertical: compact || capsule ? 4 : 7,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(capsule ? 20 : 8),
            ),
            textStyle: DesktopChrome.text(size: textSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            splashFactory: NoSplash.splashFactory,
          ).copyWith(
            side: WidgetStatePropertyAll(
              BorderSide(color: quiet ? Colors.transparent : DesktopChrome.rim),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? ink.withValues(alpha: .10)
                  : quiet
                  ? Colors.transparent
                  : ink.withValues(alpha: selected == true ? .13 : .055),
            ),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? ink.withValues(alpha: .05)
                  : Colors.transparent,
            ),
          ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null || icon != null) ...[
            leading ?? Icon(icon, size: 16),
            const SizedBox(width: 7),
          ],
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
    final control = Semantics(
      selected: selected,
      hint: semanticHint,
      child: button,
    );
    return tooltip == null
        ? control
        : Tooltip(message: tooltip!, child: control);
  }
}
