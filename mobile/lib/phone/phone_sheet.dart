import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/app_dialog.dart'
    show
        appDialogButtonStyle,
        kDialogControlRadius,
        kDialogVeilBlur,
        kSheetVeilOpacity,
        showAppDialog;

import 'settings_row.dart';
import 'tty.dart';

/// One action in a phone sheet.
class PhoneSheetAction {
  const PhoneSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.value,
    this.valueColor,
    this.enabled = true,
    this.chevron = false,
  });

  final IconData icon;
  final String label;

  /// Run AFTER the sheet has closed — see [showPhoneSheet], which pops first and then calls this.
  /// A dialog opened from here would otherwise open behind the closing sheet.
  final VoidCallback onTap;

  final bool destructive;

  /// A quiet word at the end of the row — a machine's state, on a machine row.
  final String? value;

  /// The colour of [value]; the secondary text colour when null — what a [SettingsRow]'s value
  /// is drawn in, since the two rows now sit in the same cards.
  final Color? valueColor;

  /// False draws the row dimmed and leaves the sheet open on a tap: an offline machine is listed
  /// so its absence is not a mystery, not so it can be opened.
  final bool enabled;

  /// Ends the row with a chevron: it opens a page or a picker of its own rather than acting where
  /// it stands — Harnesses, Machines, Settings on an agent's sheet.
  ///
  /// The mark a [SettingsRow] that opens something carries, so a door reads as a door on both.
  /// Without it the doors and the actions were the same row, and nothing told them apart.
  final bool chevron;
}

/// A run of rows in a phone sheet, drawn as one card — under a caption, or with none.
class PhoneSheetSection {
  PhoneSheetSection({this.caption, required this.actions, this.maxVisible});

  /// The heading over the card. Null draws the card bare, a gap below the one before it: for a
  /// run the sheet's title already names, or for a row that has to stand apart from its
  /// neighbours — the destructive one that ends an agent's sheet.
  final String? caption;
  final List<PhoneSheetAction> actions;

  /// Rows shown before an "N more" row that reveals the rest. Null shows everything.
  final int? maxVisible;

  bool _expanded = false;

  List<PhoneSheetAction> get visible {
    final max = maxVisible;
    if (_expanded || max == null || actions.length <= max) return actions;
    return actions.take(max).toList();
  }

  int get hiddenCount => actions.length - visible.length;

  void expand() => _expanded = true;
}

/// The `⋯` menu on a phone page: a title line, then its actions in inset cards.
///
/// The desktop reaches the same actions through a right-click menu, which a phone has no gesture
/// for. One sheet rather than a menu per page: the actions differ, the shape does not.
///
/// The rows sit in cards — the Settings page's own [SettingsGroup], under its [SettingsCaption] —
/// so a sheet and the pages it opens onto read as one surface. A card is also what says which rows
/// belong together: in one flat column of equal rows, the actions ON the subject and the doors to
/// other pages looked the same, and the one row that cannot be undone sat among them like the rest.
///
/// [actions] is the first card, with no caption. Each of [sections] is a card after it — under its
/// caption, or a gap below the card before when it has none. An empty section is left out.
///
/// [titleLeading] is drawn left of the title — the engine mark, on an agent's sheet — and
/// [titleDetail] under [titleParts]: machine, folder and branch.
///
/// The page behind stands on the app's sheet veil, dimmed and blurred — see [_PhoneSheetRoute].
Future<void> showPhoneSheet(
  BuildContext context, {
  required String title,
  List<PhoneSheetAction> actions = const [],
  List<PhoneSheetSection> sections = const [],
  PhoneSheetAction? titleAction,
  List<String>? titleParts,
  Widget? titleDetail,
  Widget? titleLeading,
}) {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));
  // What `showModalBottomSheet` does, with [_PhoneSheetRoute] pushed in place of its route —
  // that function has no way to take another. Every argument below is one it would pass for the
  // same call; the veil is the only difference.
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _PhoneSheetRoute<void>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      // tmux's `display-menu`, not an iOS sheet: no handle, square, the terminal's ground.
      showDragHandle: false,
      backgroundColor: Tty.of(context).ground,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) => SafeArea(
        child: _TmuxMenu(
          title: title,
          actions: actions,
          sections: sections,
          onAction: (action) {
            Navigator.of(sheetContext).pop();
            action.onTap();
          },
        ),
      ),
    ),
  );
}

/// The sheet as tmux draws a menu (`C-b <`, `display-menu`): a box in the terminal's own line,
/// the title set into its top border, one plain line per item, a rule between groups. The item
/// that destroys something is red; one that opens more ends in `▸`.
class _TmuxMenu extends StatefulWidget {
  const _TmuxMenu({
    required this.title,
    required this.actions,
    required this.sections,
    required this.onAction,
  });

  final String title;
  final List<PhoneSheetAction> actions;
  final List<PhoneSheetSection> sections;
  final void Function(PhoneSheetAction action) onAction;

  @override
  State<_TmuxMenu> createState() => _TmuxMenuState();
}

class _TmuxMenuState extends State<_TmuxMenu> {
  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final line = BorderSide(color: tty.dim);
    final groups = <List<Widget>>[
      if (widget.actions.isNotEmpty)
        [for (final action in widget.actions) _item(tty, action)],
      for (final section in widget.sections)
        if (section.actions.isNotEmpty)
          [
            if (section.caption case final caption?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: TtyText(caption.toLowerCase(), color: tty.dim),
              ),
            for (final action in section.visible) _item(tty, action),
            if (section.hiddenCount > 0)
              _item(
                tty,
                PhoneSheetAction(
                  icon: LucideIcons.ellipsis300,
                  label: '${section.hiddenCount} more',
                  onTap: () {},
                ),
                onTap: () => setState(section.expand),
              ),
          ],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The top border with the title set into it: `─ hn · M2 ──────`.
          Row(
            children: [
              SizedBox(width: 10, child: Container(height: 1, color: tty.dim)),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TtyText(widget.title, color: tty.text),
                ),
              ),
              Expanded(child: Container(height: 1, color: tty.dim)),
            ],
          ),
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: line, right: line, bottom: line),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (var g = 0; g < groups.length; g++) ...[
                    if (g > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(height: 1, color: tty.dim),
                      ),
                    ...groups[g],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(Tty tty, PhoneSheetAction action, {VoidCallback? onTap}) {
    final color = !action.enabled
        ? tty.dim
        : action.destructive
        ? tty.red
        : tty.text;
    return TtyTap(
      onTap: action.enabled ? (onTap ?? () => widget.onAction(action)) : null,
      minHeight: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: TtyText(action.label, color: color)),
            if (action.value case final value?)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TtyText(value, color: action.valueColor ?? tty.dim),
              ),
            if (action.chevron)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TtyText('▸', color: tty.dim),
              ),
          ],
        ),
      ),
    );
  }
}

/// The route [showPhoneSheet] pushes: Material's own bottom sheet, standing on the app's sheet veil
/// rather than a flat `black54` — the page dimmed to [kSheetVeilOpacity] and blurred at
/// [kDialogVeilBlur], as it is under the search sheet.
///
/// ⚠️ **Blurred, because what is behind these sheets is usually a live terminal.** Dimmed text is
/// still text: under the flat tint its lines stayed legible — and moving — and the eye went on
/// reading them instead of the rows it opened the sheet for.
///
/// The blur rides the route's own animation on the tint's curve, so the two deepen together as the
/// sheet rises and thin together as a drag pulls it down. The route's `filter` would not: that is
/// applied at full strength from the first frame to the last, so the page would go soft before the
/// tint had begun and snap sharp only once the sheet had gone.
///
/// Everything else is [ModalBottomSheetRoute]'s own — the barrier this wraps included, with its tap
/// to dismiss and its semantics.
class _PhoneSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _PhoneSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.backgroundColor,
    required super.constraints,
    required super.showDragHandle,
    required super.isScrollControlled,
  }) : super(
         modalBarrierColor: Colors.black.withValues(alpha: kSheetVeilOpacity),
       );

  @override
  Widget buildModalBarrier() {
    final animation = this.animation!;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, barrier) {
        final blur = kDialogVeilBlur * barrierCurve.transform(animation.value);
        return BackdropFilter(
          // Off while there is nothing to blur: the first frame of the way up, the last of the way
          // down.
          enabled: blur > 0,
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: barrier,
        );
      },
      child: super.buildModalBarrier(),
    );
  }
}




/// A yes/no question before something that cannot be undone — stopping a harness, unlinking a
/// machine. Returns true only if the destructive button was the one pressed; Cancel, a tap on the
/// veil and Escape all answer no.
///
/// Laid out as the rename dialog is (`widgets/rename_agent_dialog.dart`) and on the same veil —
/// [showAppDialog]'s blur under its tint — so the app's dialogs read as one set: a heading row with
/// a mark, the sentence, then Cancel and the act side by side at a thumb's size.
///
/// [icon] is the mark, on a red tile: pass the icon of the row that asked, so the question visibly
/// continues the tap that opened it. [detail], when given, goes under the title — where the thing
/// lives, so two of the same name on two machines cannot be confused at the one step that ends one.
Future<bool> confirmPhoneAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = LucideIcons.triangleAlert300,
  String? detail,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
      detail: detail,
    ),
  );
  return confirmed ?? false;
}

/// [confirmPhoneAction]'s card.
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.icon,
    required this.detail,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // The red tuned as ink on a dark surface, for the mark. [AppPalette.dangerFill] is darkened to
    // carry white lettering, so it stays on the button — the one place that has any.
    final danger = Theme.of(context).colorScheme.error;
    final detail = this.detail;
    return Dialog(
      // 16 from a phone's edges, as the rename dialog: the sentence gets the width, up to the 360
      // the card stops at on anything wider.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: title,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: danger.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          kDialogControlRadius,
                        ),
                        border: Border.all(
                          color: danger.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Icon(icon, size: 20, color: danger),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Never cut short: the name in it is what the question is about.
                          Text(
                            title,
                            style: TextStyle(
                              color: AppPalette.textPrimary,
                              fontSize: 17,
                              fontWeight: AppFont.semibold,
                              height: 1.3,
                            ),
                          ),
                          if (detail != null && detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppPalette.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    // A neutral well, not accent text, for the reason the rename dialog's Cancel
                    // is one: blue lettering on this card is 3.0:1, and a way out does not need
                    // the accent to be found.
                    Expanded(
                      child: FilledButton(
                        style: appDialogButtonStyle(
                          background: AppSurface.recess,
                          foreground: AppPalette.textPrimary,
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: appDialogButtonStyle(
                          background: AppPalette.dangerFill,
                          foreground: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
