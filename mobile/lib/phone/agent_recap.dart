import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/skeleton.dart';
import 'package:harness_mobile/state/session_preview.dart';

import 'tty.dart';
import 'tty_controls.dart';

/// What a session's last finished turn came to, as Find shows it under the
/// session's row.
class PhoneRecap {
  const PhoneRecap({
    required this.headline,
    required this.body,
    required this.bodyAddsMore,
  });

  /// One paragraph, markup and line breaks flattened out — what the folded row
  /// shows, two lines at most.
  final String headline;

  /// The reply as it was written — what the row unfolds to.
  final String body;

  /// Whether [body] says anything [headline] does not, before [headline] is
  /// even measured against the room it has: a turn's own recap is a line about
  /// a reply that is usually much longer.
  final bool bodyAddsMore;
}

/// How much of a reply is flattened into a headline. Two lines of a phone row
/// hold a small part of this; the rest is only ever read unfolded.
const _headlineSource = 600;

/// The recap [previews] holds for [key], or null when it holds none.
///
/// The headline is the turn's own `recap` where it had one
/// ([SessionPreview.recap]), paired with the reply that same summary carried —
/// never with a reply from another turn. Otherwise it is the reply on record
/// ([SessionPreview.response]), flattened: a provider that writes no recap has
/// still said something, and what it said is the truest line to show.
PhoneRecap? phoneRecap(SessionPreviewStore previews, SessionPreviewKey? key) {
  if (key == null) return null;
  final preview = previews.read(key);
  if (preview == null) return null;
  final headline = preview.recap;
  final saved = preview.savedText;
  final body = preview.response;
  // Find rebuilds on every preview the store publishes — as often as every 80 ms while an agent
  // streams — and a streamed delta moves none of these three. Same strings, same recap: the
  // flattening is not run again.
  final memo = _recaps[preview];
  if (memo != null &&
      identical(memo.headline, headline) &&
      identical(memo.saved, saved) &&
      identical(memo.body, body)) {
    return memo.recap;
  }
  final recap = _recapOf(headline, saved, body);
  _recaps[preview] = (
    headline: headline,
    saved: saved,
    body: body,
    recap: recap,
  );
  return recap;
}

/// The last recap [phoneRecap] made for each preview, with the strings it was made from. Held
/// beside the preview rather than in it, so it goes when the store lets the preview go.
final _recaps =
    Expando<
      ({String? headline, String? saved, String? body, PhoneRecap? recap})
    >('phoneRecap');

PhoneRecap? _recapOf(String? headline, String? saved, String? body) {
  if (headline != null && saved != null) {
    final flat = flattenRecap(headline);
    if (flat.isNotEmpty) {
      return PhoneRecap(
        headline: flat,
        body: saved,
        bodyAddsMore: _flattenHead(saved) != flat,
      );
    }
  }
  if (body == null) return null;
  final flat = _flattenHead(body);
  if (flat.isEmpty) return null;
  return PhoneRecap(
    headline: flat,
    body: body,
    // Cut before flattening, so the headline cannot be all of it; and a reply
    // laid out in lines or lists reads differently unfolded than run together.
    bodyAddsMore: body.length > _headlineSource || body.contains('\n'),
  );
}

String _flattenHead(String text) => flattenRecap(
  text.length > _headlineSource ? text.substring(0, _headlineSource) : text,
);

/// [text] as one plain paragraph: no headings, list markers, quote marks,
/// emphasis or code ticks, and every run of whitespace a single space.
String flattenRecap(String text) => text
    .replaceAll(
      RegExp(r'^[ \t]*(?:#{1,6}[ \t]+|[-*+][ \t]+|>[ \t]?)', multiLine: true),
      '',
    )
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The recap under one of Find's rows: two lines folded, the whole reply
/// unfolded.
///
/// ⚠️ **Its own tap target, beside the row's and not inside it.** A tap on the
/// row opens the session; a tap here only folds or unfolds. Nested in the row,
/// every tap on the recap would light the row as though it were about to open.
///
/// Folds only where there is more to see — a recap that already fits in two
/// lines and says all its reply does draws no chevron and takes no tap.
class AgentRecap extends StatelessWidget {
  const AgentRecap({
    super.key,
    required this.recap,
    required this.expanded,
    required this.onToggle,
  });

  final PhoneRecap recap;
  final bool expanded;
  final VoidCallback onToggle;

  static const _rule = 1.0;
  static const _inset = 10.0;
  static const _gap = 8.0;
  static const _chevron = 14.0;

  /// The row's own gutter, so the rule stands under the first letter of the
  /// name above it.
  static const _outer = EdgeInsets.fromLTRB(Tty.origin, 0, Tty.origin, 10);

  static TextStyle _style(Tty tty, bool expanded) =>
      tty.style(color: expanded ? tty.text : tty.faint, size: TtySize.meta);

  static Color _ruleColor(Tty tty) => tty.text.withValues(alpha: 0.16);

  /// Whether [headline] runs past two lines in [width].
  static bool _clipped(
    BuildContext context,
    String headline,
    TextStyle style,
    double width,
  ) {
    if (width <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(
        text: headline,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final clipped = painter.didExceedMaxLines;
    painter.dispose();
    return clipped;
  }

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final style = _style(tty, expanded);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.fold;
    return Padding(
      padding: _outer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textWidth =
              constraints.maxWidth - _rule - _inset - _gap - _chevron;
          final foldable =
              expanded ||
              recap.bodyAddsMore ||
              _clipped(context, recap.headline, style, textWidth);
          final framed = Container(
            padding: const EdgeInsets.only(left: _inset),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: _rule,
                  color: expanded ? tty.faint : _ruleColor(tty),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AnimatedSize(
                    duration: motion,
                    curve: AppMotion.curve,
                    alignment: Alignment.topLeft,
                    child: Text(
                      expanded ? recap.body : recap.headline,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
                if (foldable) ...[
                  const SizedBox(width: _gap),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: motion,
                      curve: AppMotion.curve,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: _chevron,
                        color: tty.faint,
                      ),
                    ),
                  ),
                ] else
                  // Keeps a folded and an unfoldable recap the same width, so
                  // their lines break at the same place down the list.
                  const SizedBox(width: _gap + _chevron),
              ],
            ),
          );
          if (!foldable) return framed;
          return Semantics(
            button: true,
            onTapHint: expanded ? 'Fold the recap' : 'Show the whole recap',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              child: framed,
            ),
          );
        },
      ),
    );
  }
}

/// The recap's place held while it is being read, so the row does not grow
/// under the reader's eye when it lands. Two lines, as a folded recap is.
class AgentRecapPlaceholder extends StatelessWidget {
  const AgentRecapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tty = Tty.of(context);
    final style = AgentRecap._style(tty, false);
    return Padding(
      padding: AgentRecap._outer,
      child: Container(
        padding: const EdgeInsets.only(
          left: AgentRecap._inset,
          right: AgentRecap._gap + AgentRecap._chevron,
        ),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: AgentRecap._rule,
              color: AgentRecap._ruleColor(tty),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonText(style: style),
            SkeletonText(style: style, widthFactor: 0.6),
          ],
        ),
      ),
    );
  }
}
