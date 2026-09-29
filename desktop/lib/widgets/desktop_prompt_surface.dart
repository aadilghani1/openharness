import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import 'desktop_chrome.dart';

/// Shared anatomy for compact desktop forms and confirmations. Callers retain
/// their scrolling, focus, keyboard handling, and operation state.
class DesktopPromptSurface extends StatelessWidget {
  const DesktopPromptSurface({
    super.key,
    required this.body,
    required this.actions,
    this.footer,
    this.width = 480,
  });

  /// Normally a scroll view, with its controller owned by the calling form.
  final Widget body;
  final List<Widget> actions;

  /// A short status or recovery message that remains beside the actions.
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DesktopChrome(
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: width,
          child: DesktopDialogSurface(
            child: Padding(
              padding: const EdgeInsets.all(DesktopChrome.panelPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: body),
                  if (footer case final footer?) ...[
                    const SizedBox(height: DesktopChrome.groupGap),
                    footer,
                  ],
                  const SizedBox(height: DesktopChrome.groupGap),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: DesktopChrome.controlGap,
                    runSpacing: DesktopChrome.controlGap,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps status and recovery details readable without displacing the actions.
/// Longer messages scroll and remain selectable in full; selection does not
/// introduce a Tab stop. Callers retain announcement and operation ownership.
class DesktopPromptMessage extends StatelessWidget {
  const DesktopPromptMessage(this.message, {super.key, this.color});

  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) => SelectableText(
    message,
    maxLines: 3,
    style: DesktopChrome.text(size: 13, color: color),
  );
}
