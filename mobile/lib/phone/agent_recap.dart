import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/session_preview.dart';

import 'find_row.dart';
import 'tty.dart';
import 'tty_controls.dart';

/// What a session's last finished turn said, as Find unfolds it under the session's row — or null
/// when [previews] holds nothing it said.
///
/// The reply the turn's own `recap` was written for, where it had one ([SessionPreview.savedText]
/// beside [SessionPreview.recap]) — never a reply from another turn. Otherwise the reply on record
/// ([SessionPreview.response]): a provider that writes no recap has still said something.
String? phoneRecap(SessionPreviewStore previews, SessionPreviewKey? key) {
  if (key == null) return null;
  final preview = previews.read(key);
  if (preview == null) return null;
  final saved = preview.savedText;
  final text = preview.recap != null && saved != null
      ? saved
      : preview.response;
  return text == null || text.trim().isEmpty ? null : text;
}

/// The chevron at the end of a Find row's first line, beside `idle · 25m`: shows the session's
/// recap under the row, and hides it again.
///
/// The recap is folded away by default — which session to open is decided by its name, state and
/// age, and what it last said is only there for the one somebody wonders about.
///
/// Given to the row as its [FindRow.accessory], which draws it over the row rather than inside it,
/// so a tap here never lights the row. Wide enough for a thumb, as tall as the row gives it, the
/// chevron centred in it; [room] is what the row keeps clear for it.
class AgentRecapToggle extends StatelessWidget {
  const AgentRecapToggle({
    super.key,
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  static const double _width = 36;
  static const double _chevron = 14;

  /// Between the row's state words and the chevron.
  static const double _gap = 8;

  /// What [FindRow.accessoryRoom] keeps for this: the gap and the chevron, less the row's own
  /// gutter, which the toggle's hit area overlaps.
  static const double room = _gap + (_width + _chevron) / 2 - Tty.origin;

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.fold;
    return Semantics(
      button: true,
      label: expanded ? 'Hide the recap' : 'Show the recap',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onToggle();
        },
        child: SizedBox(
          width: _width,
          child: Center(
            child: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: motion,
              curve: AppMotion.curve,
              child: Icon(
                LucideIcons.chevronDown,
                size: _chevron,
                color: expanded ? tty.text : tty.faint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A session's recap under its Find row: nothing while folded, the reply as it was written while
/// [expanded], growing into place rather than appearing.
///
/// ⚠️ **Its own tap target, beside the row's and not inside it.** A tap on the row opens the
/// session; a tap here folds the recap away, as the row's [AgentRecapToggle] does — the larger
/// target, and where the eye is once the reading is done.
class AgentRecap extends StatelessWidget {
  const AgentRecap({
    super.key,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  static const double _rule = 1.0;
  static const double _inset = 10.0;

  /// The row's own gutter, so the rule stands under the first letter of the name above it.
  static const _outer = EdgeInsets.fromLTRB(Tty.origin, 0, Tty.origin, 12);

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.fold;
    return AnimatedSize(
      duration: motion,
      curve: AppMotion.curve,
      alignment: Alignment.topLeft,
      child: !expanded
          ? const SizedBox(width: double.infinity)
          : Semantics(
              button: true,
              onTapHint: 'Fold the recap',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onToggle();
                },
                child: Padding(
                  padding: _outer,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(left: _inset),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: _rule, color: tty.faint),
                      ),
                    ),
                    child: Text(
                      text,
                      style: tty.style(color: tty.text, size: TtySize.meta),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
