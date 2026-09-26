/// The spread of a subsequence match, or null when the query does not match.
/// Both arguments should already be normalized for case. [from] is where in
/// [text] the match may begin.
int? subsequenceSpread(
  String text,
  String query, {
  int from = 0,
  void Function(int start, int end)? onMatch,
}) {
  if (query.isEmpty) return 0;
  var at = from - 1;
  var first = -1;
  for (final rune in query.runes) {
    final character = String.fromCharCode(rune);
    final found = text.indexOf(character, at + 1);
    if (found < 0) return null;
    if (first < 0) first = found;
    at = found;
    onMatch?.call(found, found + character.length);
  }
  return at - first;
}

final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether [index] begins a word: the start of [text], or just after a
/// character that is neither a letter nor a digit, as in "fix-auth".
bool startsWord(String text, int index) {
  if (index <= 0) return true;
  final unit = text.codeUnitAt(index - 1);
  if (unit < 0x80) {
    return !(unit >= 0x30 && unit <= 0x39 ||
        unit >= 0x41 && unit <= 0x5a ||
        unit >= 0x61 && unit <= 0x7a);
  }
  return !_wordCharacter.hasMatch(text[index - 1]);
}

/// The first occurrence of [term] at or after [start] that begins a word, or
/// -1: "port" is a word in "windows port" and only a fragment of "support".
int wordStartIndexOf(String text, String term, [int start = 0]) {
  if (term.isEmpty) return start.clamp(0, text.length);
  for (
    var at = text.indexOf(term, start);
    at >= 0;
    at = text.indexOf(term, at + 1)
  ) {
    if (startsWord(text, at)) return at;
  }
  return -1;
}

/// A scattered-letter match that starts on a word and stays close together:
/// "ath" finds "fix authentication" and "cmd" finds "command", but "auth" no
/// longer finds every folder under ".../autonomous-harness/...". Returns the
/// tightest such spread, or null; [onMatch] receives the letters it used.
int? wordSubsequenceSpread(
  String text,
  String query, {
  void Function(int start, int end)? onMatch,
}) {
  if (query.isEmpty) return 0;
  final first = String.fromCharCode(query.runes.first);
  final limit = query.length * 2;
  int? bestStart, bestSpread;
  for (
    var at = text.indexOf(first);
    at >= 0;
    at = text.indexOf(first, at + first.length)
  ) {
    if (!startsWord(text, at)) continue;
    final spread = subsequenceSpread(text, query, from: at);
    // A later start sees less of the text, so it cannot match either.
    if (spread == null) break;
    if (spread <= limit && (bestSpread == null || spread < bestSpread)) {
      bestStart = at;
      bestSpread = spread;
      if (spread == query.length - 1) break;
    }
  }
  if (bestStart != null && onMatch != null) {
    subsequenceSpread(text, query, from: bestStart, onMatch: onMatch);
  }
  return bestSpread;
}
