import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harness_mobile/daemons/card.dart';
import 'package:harness_mobile/daemons/daemon_face.dart';
import 'package:harness_mobile/daemons/daemon_lines.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';
import 'package:harness_mobile/daemons/zoo_client.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart' show AppFont;

import 'daemon_hatch.dart';
import 'daemon_scope.dart';
import 'daemon_style.dart';

/// Open the daemon's sheet: it looks back at you (one blink), and the zoo is
/// read again so a new egg from a computer is there when the sheet is.
Future<void> showDaemonSheet(BuildContext context, DaemonHostState host) {
  host.face.look();
  unawaited(host.zoo.refresh());
  final navigator = Navigator.of(context, rootNavigator: true);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: DaemonInk.ground,
    barrierColor: Colors.black.withValues(alpha: .55),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    builder: (sheetContext) => DaemonSheet(
      face: host.face,
      facts: () => host.facts,
      onHatch: (egg) {
        Navigator.of(sheetContext).pop();
        unawaited(hatchEgg(navigator, host.face, egg));
      },
    ),
  );
}

/// The daemon's sheet: its portrait at its version and mood, its names, the
/// line it would say now, its lore and lineage, the zoo as a shelf (tap one
/// to pair it), and the eggs waiting. Before any daemon: the nest, and the
/// habits that bring the first egg.
class DaemonSheet extends StatelessWidget {
  const DaemonSheet({
    super.key,
    required this.face,
    required this.facts,
    required this.onHatch,
  });

  final DaemonFace face;
  final DaemonFacts Function() facts;
  final void Function(ZooEgg egg) onHatch;

  ZooClient get zoo => face.zoo;
  DaemonRoster get roster => face.roster;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([face, zoo]),
    builder: (context, _) {
      final def = face.def;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            Flexible(
              child: ListView(
                key: const ValueKey('daemon-sheet'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: def == null ? _nest(context) : _daemon(context, def),
              ),
            ),
          ],
        ),
      );
    },
  );

  // ── with a daemon ──────────────────────────────────────────────────────────

  List<Widget> _daemon(BuildContext context, DaemonDef def) {
    final daemon = face.daemon!;
    final mood = face.mood;
    final line = daemonLine(roster, def, mood, facts());
    final nick = daemon.nickname;
    final rarity =
        '${daemon.shiny ? 'SHINY ' : ''}${def.rarity.toUpperCase()}'
        '  ${cardNumber(roster, def)}';
    return [
      _Panel(
        key: const ValueKey('daemon-portrait'),
        pitch: def.darkOnly,
        semantics: '${def.id} ${daemon.version}, ${DaemonFace.moodWords[mood]}',
        child: _Art(face.portrait, colour: def.color, size: 14),
      ),
      const SizedBox(height: 14),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(
            face.name,
            key: const ValueKey('daemon-name'),
            style: DaemonInk.sans(
              size: 24,
              color: DaemonInk.bright,
              weight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            nick == null ? daemon.version : '${def.id} ${daemon.version}',
            style: DaemonInk.mono(size: 14, color: def.color),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        rarity,
        style: DaemonInk.mono(size: 12, color: DaemonInk.rarity(def.rarity)),
      ),
      const SizedBox(height: 12),
      _Said(
        key: const ValueKey('daemon-line'),
        text: '${face.name}: $line',
        alert: _Said.alerts(mood),
      ),
      const SizedBox(height: 14),
      Text(def.lore, style: DaemonInk.sans(size: 14.5)),
      const SizedBox(height: 10),
      Text(def.familyLine, style: DaemonInk.mono(size: 13)),
      if (def.familyYears.isNotEmpty)
        Text(
          def.familyYears,
          style: DaemonInk.mono(size: 12, color: DaemonInk.faint),
        ),
      const SizedBox(height: 8),
      Text(
        _bondLine(daemon),
        style: DaemonInk.mono(size: 12, color: DaemonInk.dim),
      ),
      if (zoo.zoo.eggs.isNotEmpty) ...[const _Caption('EGGS'), ..._eggRows()],
      const _Caption('ZOO'),
      _Shelf(zoo: zoo, roster: roster),
    ];
  }

  String _bondLine(ZooDaemon daemon) {
    final rules = roster.rules;
    final last = rules.bondLevels.length - 1;
    final next = rules.versions
        .where((v) => (rules.bondForVersion[v] ?? 0) > daemon.bond)
        .firstOrNull;
    return 'bond ${daemon.bond}/$last  ${daemon.xp} xp'
        '${next == null ? '' : '  $next at bond ${rules.bondForVersion[next]}'}';
  }

  // ── before any daemon: the nest ────────────────────────────────────────────

  List<Widget> _nest(BuildContext context) {
    final rules = roster.rules;
    final ready = zoo.readyEgg != null;
    final done = zoo.zoo.habits.toSet();
    final glyph = face.glyph;
    return [
      _Panel(
        key: const ValueKey('daemon-nest'),
        semantics: ready
            ? 'An egg, ready to hatch'
            : 'A nest: ${done.length} of ${zoo.habitsNeeded} habits',
        child: _Art(
          [glyph],
          colour: ready ? DaemonInk.yellow : DaemonInk.dim,
          size: 30,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        ready ? 'Your egg is ready' : 'A daemon is incubating',
        style: DaemonInk.sans(
          size: 22,
          color: DaemonInk.bright,
          weight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        ready
            ? 'Open it to meet the daemon that pairs with you on every '
                  'device.'
            : 'The first egg arrives after ${zoo.habitsNeeded} of these, '
                  'in any order. ${done.length} done.',
        style: DaemonInk.sans(size: 14.5, color: DaemonInk.dim),
      ),
      if (!ready) ...[
        const SizedBox(height: 12),
        for (final habit in rules.habits)
          _Habit(label: habit.label, done: done.contains(habit.key)),
      ],
      if (zoo.zoo.eggs.isNotEmpty) ...[const _Caption('EGGS'), ..._eggRows()],
    ];
  }

  List<Widget> _eggRows() => [
    for (final egg in zoo.zoo.eggs)
      _EggRow(
        look: face.eggLook(egg),
        kind: egg.kind,
        date: egg.date,
        busy: zoo.hatchingEgg != null,
        onHatch: () => onHatch(egg),
      ),
  ];
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: DaemonInk.line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A box of night for art: deep, or pitch black for a daemon that only shows
/// in the dark.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.child,
    required this.semantics,
    this.pitch = false,
  });

  final Widget child;
  final String semantics;
  final bool pitch;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    image: true,
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: pitch ? DaemonInk.pitch : DaemonInk.deep,
        border: Border.all(color: DaemonInk.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    ),
  );
}

/// Lines of ASCII art, kept in their columns and scaled down to fit a narrow
/// screen rather than wrapped. Text size does not grow art: it would only be
/// scaled back down to fit.
class _Art extends StatelessWidget {
  const _Art(this.lines, {required this.colour, this.size = 13});

  final List<String> lines;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        lines.join('\n'),
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: DaemonInk.mono(size: size, color: colour, height: 1.2),
      ),
    ),
  );
}

/// The line it would say now. Only what needs you takes tmux's yellow message
/// line: a harness waiting on you, and a failure. Anything else — content,
/// working, a boop — is dim text, the way the status line stays quiet
/// (`daemons/README.md`, Voice).
class _Said extends StatelessWidget {
  const _Said({super.key, required this.text, required this.alert});

  final String text;
  final bool alert;

  static bool alerts(DaemonMood mood) =>
      mood == DaemonMood.need || mood == DaemonMood.fail;

  @override
  Widget build(BuildContext context) {
    if (!alert) {
      return Text(
        text,
        style: DaemonInk.mono(size: 13, color: DaemonInk.dim, height: 1.35),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: DaemonInk.yellow,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: DaemonInk.mono(size: 13, color: DaemonInk.pitch, height: 1.35),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: DaemonInk.mono(
          size: 12,
          color: DaemonInk.faint,
          weight: FontWeight.w600,
        ).copyWith(letterSpacing: 1.6),
      ),
    ),
  );
}

class _Habit extends StatelessWidget {
  const _Habit({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, ${done ? 'done' : 'not yet'}',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done ? '[x]' : '[ ]',
            style: DaemonInk.mono(
              size: 13.5,
              color: done ? DaemonInk.green : DaemonInk.faint,
              height: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: DaemonInk.sans(
                size: 14.5,
                color: done ? DaemonInk.ink : DaemonInk.dim,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EggRow extends StatelessWidget {
  const _EggRow({
    required this.look,
    required this.kind,
    required this.date,
    required this.busy,
    required this.onHatch,
  });

  final String look, kind;
  final String? date;
  final bool busy;
  final VoidCallback onHatch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Text(
            look,
            textScaler: TextScaler.noScaling,
            style: DaemonInk.mono(size: 14, color: DaemonInk.yellow),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$kind egg${date == null ? '' : ', $date'}',
            style: DaemonInk.sans(size: 14.5),
          ),
        ),
        TextButton(
          key: ValueKey('daemon-hatch-$kind'),
          onPressed: busy
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onHatch();
                },
          style: TextButton.styleFrom(
            foregroundColor: DaemonInk.yellow,
            disabledForegroundColor: DaemonInk.faint,
            minimumSize: const Size(64, 44),
          ),
          child: Text(
            'Hatch',
            style: TextStyle(
              fontFamily: AppFont.sans,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The zoo as a box back: owned sprites in their colours, `[ ? ]` for a
/// numbered slot still empty, `[ ! ]` for a secret. Laid out to the screen
/// (card.mjs's five to a row is fifty columns, wider than a phone), and a tap
/// on a daemon you own pairs it.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.zoo, required this.roster});

  final ZooClient zoo;
  final DaemonRoster roster;

  @override
  Widget build(BuildContext context) {
    final owned = zoo.zoo.ownedIds;
    final pair = zoo.paired?.id;
    final cells = shelfCells(roster, owned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          shelfTitle(roster, owned),
          style: DaemonInk.mono(size: 12.5, color: DaemonInk.dim),
        ),
        const SizedBox(height: 10),
        // An even grid, as many slots to a row as fit: a box back, whatever
        // the width of the phone.
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0, least = 84.0;
            final columns = ((constraints.maxWidth + gap) / (least + gap))
                .floor()
                .clamp(1, 5);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final cell in cells)
                  SizedBox(
                    width: width,
                    child: _ShelfCell(
                      cell: cell,
                      paired: cell.daemon?.id == pair,
                      onPair: cell.daemon == null || cell.daemon!.id == pair
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              zoo.pair(cell.daemon!.id);
                            },
                    ),
                  ),
              ],
            );
          },
        ),
        if (owned.length > 1) ...[
          const SizedBox(height: 10),
          Text(
            'Tap a daemon to pair it. The pair is the same on every device.',
            style: DaemonInk.sans(size: 13, color: DaemonInk.faint),
          ),
        ],
      ],
    );
  }
}

class _ShelfCell extends StatelessWidget {
  const _ShelfCell({required this.cell, required this.paired, this.onPair});

  final ShelfCell cell;
  final bool paired;
  final VoidCallback? onPair;

  @override
  Widget build(BuildContext context) {
    final d = cell.daemon;
    final label = d == null
        ? (cell.label == 'secret'
              ? 'A secret, not found yet'
              : 'Number ${cell.label.substring(1)}, not hatched yet')
        : '${d.id}${paired ? ', paired' : ''}';
    return Semantics(
      key: ValueKey('daemon-shelf-${d?.id ?? cell.label}'),
      button: onPair != null,
      selected: paired,
      label: label,
      hint: onPair == null ? null : 'Pairs it',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPair,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: DaemonInk.deep,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: paired ? d!.color : DaemonInk.line,
              width: paired ? 1.5 : 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cell.top,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: DaemonInk.mono(
                    size: 13,
                    color: d?.color ?? DaemonInk.faint,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  paired ? '${cell.label} *' : cell.label,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: DaemonInk.mono(
                    size: 11,
                    color: d == null ? DaemonInk.faint : DaemonInk.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
