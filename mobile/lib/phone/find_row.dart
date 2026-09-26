import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fzf.dart' show fzfHighlight;
import 'tty.dart';
import 'tty_controls.dart';

/// One of Find's rows: two lines, 60pt — the name at 17 with its state word at the right edge, and
/// under it where the harness works (or, while it asks, its question).
///
/// ```
/// api-fix                               asking
/// "Run the migration on the test db?"
/// docs-rewrite                         working
/// M2:site · docs-v2 · 2m
/// ```
class FindRow extends StatelessWidget {
  const FindRow({
    super.key,
    required this.title,
    this.detail,
    this.detailColor,
    this.state,
    this.stateColor,
    this.terms = const [],
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  final String title;

  /// Line 2: `machine:folder · branch · age`, or a quoted question.
  final String? detail;
  final Color? detailColor;

  /// `asking`, `working`, `idle`, `exited` — one word, right-aligned on line 1.
  final String? state;
  final Color? stateColor;

  /// What was typed, lit green in [title] and [detail].
  final List<String> terms;

  /// The row Return opens: the raised ground behind it.
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final ink = enabled ? tty.text : tty.faint;
    return TtyTap(
      minHeight: height,
      onTap: enabled && onTap != null
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      child: ColoredBox(
        color: selected ? ttyRaised(tty) : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: fzfHighlight(
                          title,
                          terms,
                          base: tty.style(
                            color: ink,
                            size: TtySize.row,
                            weight: FontWeight.w600,
                          ),
                          hit: tty.style(
                            color: tty.green,
                            size: TtySize.row,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (state case final state?) ...[
                    const SizedBox(width: 12),
                    TtyText(
                      state,
                      color: stateColor ?? tty.faint,
                      size: TtySize.meta,
                    ),
                  ],
                ],
              ),
              if (detail case final detail? when detail.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: fzfHighlight(
                      detail,
                      terms,
                      base: tty.style(
                        color: detailColor ?? tty.faint,
                        size: TtySize.meta,
                      ),
                      hit: tty.style(color: tty.green, size: TtySize.meta),
                    ),
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The `+` row that ends a list: `+ New Harness`, `+ Open Folder`. Cyan, the colour of what can be
/// tapped; an optional faint second line says where.
class FindAddRow extends StatelessWidget {
  const FindAddRow({
    super.key,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return TtyTap(
      minHeight: detail == null ? 52 : FindRow.height,
      semanticsLabel: label,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TtyText(
              '+ $label',
              color: onTap == null ? tty.faint : tty.cyan,
              size: TtySize.row,
              weight: FontWeight.w600,
            ),
            if (detail case final detail?) ...[
              const SizedBox(height: 3),
              TtyText(detail, color: tty.faint, size: TtySize.meta),
            ],
          ],
        ),
      ),
    );
  }
}

/// Find's section header — `needs you`, `recent`, `commands`: 13pt, faint, 28pt tall.
class FindHeader extends StatelessWidget {
  const FindHeader(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TtyText(text, color: color ?? tty.faint, size: TtySize.meta),
      ),
    );
  }
}
