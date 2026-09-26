/// The Dart port of `daemons/tools/card.mjs`: the card people share and the
/// zoo as a shelf, as printable ASCII. `test/daemons/render_frames_test.dart`
/// checks every card against `daemons/frames.json`.
///
/// A card never shows a live mood: it is a portrait, not a presence indicator.
library;

import 'render.dart';
import 'roster.dart';

const cardWidth = 42;
const _inner = cardWidth - 4;

List<DaemonDef> _regulars(DaemonRoster roster) =>
    roster.daemons.where((d) => d.rarity != 'secret').toList();

/// `#03/09`, or `#S/09` for a secret: secrets sit outside the numbered set.
String cardNumber(DaemonRoster roster, DaemonDef d) {
  final set = _regulars(roster).where((x) => x.drop == d.drop).toList();
  final of = set.length.toString().padLeft(2, '0');
  if (d.rarity == 'secret') return '#S/$of';
  return '#${(set.indexOf(d) + 1).toString().padLeft(2, '0')}/$of';
}

/// Words wrapped the way card.mjs wraps them.
List<String> wrapWords(String text, int width) {
  final out = <String>[];
  var line = '';
  for (final word in text.split(' ')) {
    if ('$line $word'.trim().length > width) {
      out.add(line.trim());
      line = word;
    } else {
      line += ' $word';
    }
  }
  if (line.trim().isNotEmpty) out.add(line.trim());
  return out;
}

/// The card as lines of printable ASCII, 42 columns wide: the portrait at its
/// version, the number, rarity, name, lineage and first words.
List<String> cardLines(
  DaemonRoster roster,
  DaemonDef d, {
  String? version,
  bool shiny = false,
  int? serial,
  String? nickname,
  String? hatched,
  String? egg,
}) {
  final v = version ?? roster.rules.versions.first;
  final drop = roster.drop(d.drop) ?? DaemonDrop(d.drop, 1, d.drop);
  String row(String s) {
    final padded = s.padRight(_inner);
    return '| ${padded.substring(0, _inner)} |';
  }

  final head = '${cardNumber(roster, d)}  DROP ${drop.n}: '
      '${drop.name.toUpperCase()}';
  final rarity = '${shiny ? 'SHINY ' : ''}${d.rarity.toUpperCase()}';
  final gap = _inner - head.length - rarity.length;
  final name =
      '${nickname != null ? '$nickname the ' : ''}${d.id} $v'
      '${serial != null ? '  #${serial.toString().padLeft(4, '0')}' : ''}';
  final portrait = renderPortrait(roster, d, v, DaemonMood.idle, motion: false);
  final width = portrait.fold<int>(0, (w, l) => l.length > w ? l.length : w);
  final pad = ((_inner - width) / 2).floor();
  final left = ' ' * (pad < 0 ? 0 : pad);
  var stamp = '  hatched ${hatched ?? ''}${egg != null ? ', $egg egg' : ''}';
  stamp = stamp.replaceFirst(RegExp(r'\s+,'), ',');
  return [
    '.${'-' * (cardWidth - 2)}.',
    row('$head${' ' * (gap < 1 ? 1 : gap)}$rarity'),
    row(''),
    for (final line in portrait) row('$left$line'),
    row(''),
    row('  $name'),
    row('  ${d.familyLine}'),
    row(''),
    for (final line in wrapWords('"${d.first}"', _inner - 2)) row('  $line'),
    if (hatched != null || egg != null) ...[row(''), row(stamp)],
    "'${'-' * (cardWidth - 2)}'",
  ];
}

/// The card as it is shared: inside a fenced code block, so it keeps its
/// columns in Slack, GitHub and a chat app.
String fencedCard(List<String> lines) => '```\n${lines.join('\n')}\n```';

/// One slot on a shelf: an owned daemon's sprite, or `[ ? ]` for a numbered
/// slot still empty, `[ ! ]` for a secret not found yet.
class ShelfCell {
  const ShelfCell({required this.top, required this.label, this.daemon});

  /// The sprite, or `[ ? ]`/`[ ! ]`.
  final String top;

  /// The daemon's id, its number (`#03`), or `secret`.
  final String label;

  /// The owned daemon, for its colour; null for an empty slot.
  final DaemonDef? daemon;

  bool get owned => daemon != null;
}

/// The shelf's slots for a drop, in roster order.
List<ShelfCell> shelfCells(
  DaemonRoster roster,
  Iterable<String> ownedIds, {
  String? drop,
}) {
  final owned = ownedIds.toSet();
  final id = drop ?? roster.drops.first.id;
  return [
    for (final d in roster.daemons.where((d) => d.drop == id))
      if (!owned.contains(d.id))
        ShelfCell(
          top: d.secret ? '[ ! ]' : '[ ? ]',
          label: d.secret ? 'secret' : cardNumber(roster, d).substring(0, 3),
        )
      else
        ShelfCell(
          top: renderSprite(
            roster,
            d,
            roster.rules.versions.length - 1,
            DaemonMood.idle,
            motion: false,
          ),
          label: d.id,
          daemon: d,
        ),
  ];
}

/// `zoo: drop 1 unix  3/9  +secret`
String shelfTitle(DaemonRoster roster, Iterable<String> ownedIds, {String? drop}) {
  final owned = ownedIds.toSet();
  final id = drop ?? roster.drops.first.id;
  final set = roster.daemons.where((d) => d.drop == id).toList();
  final info = roster.drop(id);
  final have = set.where((d) => owned.contains(d.id) && !d.secret).length;
  final of = set.where((d) => !d.secret).length;
  final secret = set.any((d) => d.secret && owned.contains(d.id));
  return 'zoo: drop ${info?.n ?? 1} ${info?.name ?? id}  $have/$of'
      '${secret ? '  +secret' : ''}';
}

/// The shelf as text, five slots to a row, ten columns each: card.mjs's
/// `shelfLines`, for sharing. The sheet lays the same [shelfCells] out to fit
/// the screen instead.
List<String> shelfLines(
  DaemonRoster roster,
  Iterable<String> ownedIds, {
  String? drop,
}) {
  final cells = shelfCells(roster, ownedIds, drop: drop);
  final rows = <String>[];
  for (var i = 0; i < cells.length; i += 5) {
    final slice = cells.sublist(i, i + 5 > cells.length ? cells.length : i + 5);
    rows.add(slice.map((c) => c.top.padRight(10)).join().trimRight());
    rows.add(slice.map((c) => c.label.padRight(10)).join().trimRight());
    rows.add('');
  }
  final all = [shelfTitle(roster, ownedIds, drop: drop), '', ...rows];
  return all.sublist(0, all.length - 1);
}

/// `[ * SHINY * RARE ]  #05/09`, the hatch reveal's stamp.
String rarityStamp(DaemonRoster roster, DaemonDef d, {required bool shiny}) =>
    '[ ${shiny ? '* SHINY * ' : ''}${d.rarity.toUpperCase()} ]  '
    '${cardNumber(roster, d)}';
