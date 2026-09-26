import 'package:harness_mobile/terminal/question_pane.dart';

/// One answer key on the prompt bar: what it says and the digit it presses.
typedef QuestionKey = ({String label, String number});

/// The keys for an open Claude/Codex dialog, as the status line draws them in prompt mode —
/// ` 1 yes │ 2 always │ 3 no `.
///
/// A row's label is shortened to its first word or two: lowercased, cut at a `,` or `(`, and a row
/// that means "don't ask again" / "allow all" is called `always` — the word a person would say.
List<QuestionKey> questionKeys(QuestionPaneView view) => [
  for (final row in view.rows) (label: _short(row.label), number: row.number),
];

String _short(String label) {
  final lower = label.toLowerCase().trim();
  if (lower.contains("don't ask again") ||
      lower.contains('do not ask again') ||
      lower.contains('allow all') ||
      lower.contains('always')) {
    return 'always';
  }
  final cut = lower.split(RegExp(r'[,(]')).first.trim();
  final words = cut.split(RegExp(r'\s+'));
  return words.length <= 2 ? cut : words.take(2).join(' ');
}

/// What a spoken reply means to an open dialog: the key it presses, and anything said after it
/// ("no, use dist/ instead" → key 3, then "use dist/ instead" once the dialog has closed). Null when
/// it matches no answer — the caller then sends NOTHING: a reply that is not an answer must never
/// reach the dialog as keystrokes and a Return.
({String number, String? rest})? matchSpokenAnswer(
  String spoken,
  QuestionPaneView view,
) {
  final text = spoken.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '');
  if (text.isEmpty || view.rows.isEmpty) return null;
  final keys = questionKeys(view);
  String? numberWhere(bool Function(QuestionKey key) test) =>
      keys.where(test).firstOrNull?.number;

  final head = text.split(RegExp(r'[,;]|\s+—\s+')).first.trim();
  final rest = text.length > head.length
      ? text.substring(head.length).replaceFirst(RegExp(r'^[,;\s—]+'), '')
      : null;
  const ordinals = {
    'one': '1',
    'first': '1',
    'two': '2',
    'second': '2',
    'to': '2',
    'too': '2',
    'three': '3',
    'third': '3',
    'four': '4',
    'fourth': '4',
    'five': '5',
  };
  final digit =
      RegExp(r'^(?:option\s+|number\s+)?(\d)$').firstMatch(head)?.group(1) ??
      ordinals[head.replaceFirst(RegExp(r'^(?:option|number)\s+'), '')];
  if (digit != null && keys.any((key) => key.number == digit)) {
    return (number: digit, rest: _nonEmpty(rest));
  }
  if (RegExp(r'^(always|yes always|allow all|always allow)$').hasMatch(head)) {
    final always = numberWhere((key) => key.label == 'always');
    if (always != null) return (number: always, rest: _nonEmpty(rest));
  }
  if (RegExp(r'^(yes|yeah|yep|yup|sure|ok|okay|go ahead|do it|approve)$')
      .hasMatch(head)) {
    final yes = numberWhere((key) => key.label.startsWith('yes'));
    if (yes != null) return (number: yes, rest: _nonEmpty(rest));
  }
  if (RegExp(r'^(no|nope|nah|don.?t|stop|deny)$').hasMatch(head)) {
    final no = numberWhere((key) => key.label.startsWith('no'));
    if (no != null) return (number: no, rest: _nonEmpty(rest));
  }
  // An answer said in its own words: "yes and don't ask again" / "no and tell claude".
  for (final key in keys) {
    if (key.label.length > 2 && text.startsWith(key.label)) {
      return (number: key.number, rest: null);
    }
  }
  return null;
}

String? _nonEmpty(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
