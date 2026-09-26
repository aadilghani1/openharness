import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harness_mobile/daemons/card.dart';
import 'package:harness_mobile/daemons/daemon_face.dart';
import 'package:harness_mobile/daemons/render.dart';
import 'package:harness_mobile/daemons/roster.dart';
import 'package:harness_mobile/daemons/zoo.dart';
import 'package:harness_mobile/daemons/zoo_client.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart' show AppFont;

import 'daemon_style.dart';

/// Open [egg] on the server and show the reveal over everything. The chip
/// keeps the egg until the reveal has named the hatchling (or was closed),
/// and the daemon then arrives with a slow blink.
Future<void> hatchEgg(
  NavigatorState navigator,
  DaemonFace face,
  ZooEgg egg,
) async {
  final zoo = face.zoo;
  if (zoo.hatchingEgg != null) return;
  face.beginReveal();
  final result = zoo.hatch(egg.id);
  try {
    await navigator.push(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, _, _) => DaemonHatchReveal(
          roster: face.roster,
          egg: egg,
          result: result,
          zoo: zoo,
          onRevealed: face.endReveal,
        ),
      ),
    );
  } finally {
    face.endReveal();
  }
}

/// Where the reveal is. Exposed so tests and review captures can draw any
/// moment of it.
enum HatchStage { egg, pitch, silhouette, colour, banner, card, failed }

/// A still of the reveal, for review captures.
@immutable
class HatchFrame {
  const HatchFrame({
    required this.stage,
    this.egg,
    this.sprite,
    this.bannerRows = 0,
  });
  final HatchStage stage;
  final String? egg, sprite;
  final int bannerRows;
}

/// The hatch reveal, full screen (`daemons/README.md`, Hatching): the egg
/// wobbles twice (and keeps wobbling while the server answers), cracks — with
/// a tap of haptics — and its top pops; the 0.1 sprite appears as `#` in the
/// faint colour for 850 ms, fills with its colour and blinks; its name types
/// in, a row at a time, as a banner in the face from `daemons/banner.json`
/// ([renderBanner]); the rarity stamp and first words appear; then the
/// card, which copies as a fenced code block. A secret's reveal (a daemon that
/// shows only in the dark) starts pitch black. Reduce Motion goes straight to
/// the card. It can be closed at any moment; [onRevealed] runs once, when the
/// daemon may be named elsewhere.
class DaemonHatchReveal extends StatefulWidget {
  const DaemonHatchReveal({
    super.key,
    required this.roster,
    required this.egg,
    required this.result,
    required this.zoo,
    this.onRevealed,
    this.still,
  });

  final DaemonRoster roster;
  final ZooEgg egg;
  final Future<ZooHatch?> result;

  /// The zoo, for the hatchling's date.
  final ZooClient zoo;
  final VoidCallback? onRevealed;

  /// Draw one fixed moment instead of running (tests and captures only).
  final HatchFrame? still;

  @override
  State<DaemonHatchReveal> createState() => _DaemonHatchRevealState();
}

class _DaemonHatchRevealState extends State<DaemonHatchReveal> {
  /// The banner's type: 18pt cells fit the widest name in the roster (grue,
  /// 25 columns, 270pt at a monospace face's 0.6em advance) inside the 280pt a
  /// 320pt-wide screen leaves between the reveal's margins. A wider face or a
  /// wider name is scaled down to fit, never wrapped.
  static const _bannerSize = 18.0;
  static const _bannerHeight = 1.15;

  HatchStage _stage = HatchStage.egg;
  late String _egg = eggFrame(widget.roster);
  String? _sprite;
  bool _faint = false;
  int _bannerRows = 0;
  ZooHatch? _hatch;
  bool _closed = false, _revealed = false, _started = false;
  bool _reduceMotion = false;
  String? _note;

  DaemonRoster get roster => widget.roster;
  DaemonDef? get _def => roster.byId(_hatch?.daemonId);

  @override
  void initState() {
    super.initState();
    final still = widget.still;
    if (still == null) return;
    _started = true;
    _stage = still.stage;
    _egg = still.egg ?? _egg;
    _sprite = still.sprite;
    _faint = still.stage == HatchStage.silhouette;
    _bannerRows = still.bannerRows;
    unawaited(
      widget.result.then((hatch) {
        if (mounted) setState(() => _hatch = hatch);
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_started) {
      _started = true;
      unawaited(_run());
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<bool> _wait(int ms) async {
    if (_reduceMotion) return !_closed && mounted;
    await Future<void>.delayed(Duration(milliseconds: ms));
    return !_closed && mounted;
  }

  void _show(VoidCallback change) {
    if (_closed || !mounted) return;
    setState(change);
  }

  Future<void> _run() async {
    var answered = false;
    unawaited(
      widget.result.then(
        (_) => answered = true,
        onError: (_) => answered = true,
      ),
    );
    // The egg wobbles twice, and keeps wobbling while the server answers.
    var wobbles = 0;
    while (!_reduceMotion && (wobbles < 2 || !answered)) {
      for (final offset in const [-1, 0, 1, 0]) {
        _show(() => _egg = eggFrame(roster, offset: offset));
        if (!await _wait(90)) return;
      }
      if (!await _wait(420)) return;
      wobbles++;
      if (wobbles > 40) break;
    }
    ZooHatch? hatch;
    try {
      hatch = await widget.result;
    } catch (_) {
      hatch = null;
    }
    if (_closed || !mounted) return;
    if (hatch == null || roster.byId(hatch.daemonId) == null) {
      _show(() => _stage = HatchStage.failed);
      return;
    }
    _hatch = hatch;
    if (!_reduceMotion) {
      // Crack, shake, crack wider, pop.
      unawaited(HapticFeedback.mediumImpact());
      _show(() => _egg = eggFrame(roster, crack: 1));
      if (!await _wait(450)) return;
      for (final offset in const [-1, 1, -1, 1, 0]) {
        _show(() => _egg = eggFrame(roster, offset: offset, crack: 1));
        if (!await _wait(60)) return;
      }
      unawaited(HapticFeedback.mediumImpact());
      _show(() => _egg = eggFrame(roster, crack: 2));
      if (!await _wait(520)) return;
      _show(() => _egg = eggPopFrame(roster));
      if (!await _wait(480)) return;
    }
    final def = _def!;
    final sprite = renderSprite(roster, def, 0, DaemonMood.idle);
    if (!_reduceMotion) {
      if (def.darkOnly) {
        _show(() => _stage = HatchStage.pitch);
        if (!await _wait(1600)) return;
      }
      _show(() {
        _stage = HatchStage.silhouette;
        _sprite = silhouette(sprite);
        _faint = true;
      });
      if (!await _wait(850)) return;
      _show(() {
        _stage = HatchStage.colour;
        _sprite = sprite;
        _faint = false;
      });
      if (!await _wait(320)) return;
      _show(
        () => _sprite = renderSprite(
          roster,
          def,
          0,
          DaemonMood.idle,
          lid: def.lid ?? '-',
        ),
      );
      if (!await _wait(120)) return;
      _show(() => _sprite = sprite);
      if (!await _wait(220)) return;
      final rows = renderBanner(daemonBanner, def.id).length;
      for (var row = 1; row <= rows; row++) {
        _show(() {
          _stage = HatchStage.banner;
          _bannerRows = row;
        });
        if (!await _wait(90)) return;
      }
    }
    _show(() {
      _stage = HatchStage.card;
      _sprite = sprite;
      _faint = false;
      _bannerRows = renderBanner(daemonBanner, def.id).length;
    });
    _markRevealed();
  }

  void _markRevealed() {
    if (_revealed) return;
    _revealed = true;
    widget.onRevealed?.call();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _markRevealed();
    Navigator.of(context).maybePop();
  }

  List<String>? get _card {
    final def = _def, hatch = _hatch;
    if (def == null || hatch == null) return null;
    final born = widget.zoo.zoo.daemons.where((d) => d.id == def.id).lastOrNull;
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return cardLines(
      roster,
      def,
      version: roster.rules.versions.first,
      shiny: hatch.shiny,
      hatched: born?.hatchedDay ?? today,
      egg: widget.egg.kind,
    );
  }

  Future<void> _share() async {
    final card = _card;
    if (card == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: fencedCard(card)));
      if (mounted) {
        setState(() => _note = 'Copied as a code block. Paste it anywhere.');
      }
    } catch (_) {
      if (mounted) setState(() => _note = 'Could not copy the card.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final pitch =
        def?.darkOnly == true &&
        _stage != HatchStage.failed &&
        _stage != HatchStage.egg;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _markRevealed();
      },
      child: Scaffold(
        key: const ValueKey('daemon-hatch'),
        backgroundColor: pitch ? DaemonInk.pitch : DaemonInk.deep,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 80).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _children(pitch),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  key: const ValueKey('daemon-hatch-close'),
                  tooltip: 'Close',
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: DaemonInk.dim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _art(String text, TextStyle style, {Key? key, String? semantics}) =>
      Semantics(
        label: semantics,
        excludeSemantics: semantics != null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            key: key,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: style,
          ),
        ),
      );

  /// The name as a banner, [shown] rows of it typed in so far. The whole
  /// banner is laid out from the first row, unseen, so the reveal neither
  /// jumps nor rescales as the rest arrive.
  Widget _banner(List<String> rows, int shown, String name) {
    final style = DaemonInk.mono(
      size: _bannerSize,
      color: DaemonInk.bright,
      height: _bannerHeight,
    );
    Widget text(String data, {Key? key}) => Text(
      data,
      key: key,
      softWrap: false,
      textScaler: TextScaler.noScaling,
      style: style,
    );
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: text(rows.join('\n')),
            ),
            text(
              rows.take(shown).join('\n'),
              key: const ValueKey('daemon-hatch-banner'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _children(bool pitch) {
    final def = _def;
    if (_stage == HatchStage.failed) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(
            'The egg did not open.',
            key: const ValueKey('daemon-hatch-failed'),
            textAlign: TextAlign.center,
            style: DaemonInk.sans(
              size: 20,
              color: DaemonInk.bright,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The zoo could not be reached. The egg is still in your nest.',
          textAlign: TextAlign.center,
          style: DaemonInk.sans(size: 15, color: DaemonInk.dim),
        ),
        const SizedBox(height: 20),
        _button('Close', _close, key: const ValueKey('daemon-hatch-done')),
      ];
    }
    if (_stage == HatchStage.egg || def == null) {
      return [
        _art(
          _egg,
          DaemonInk.mono(size: 22, color: DaemonInk.yellow, height: 1.15),
          key: const ValueKey('daemon-hatch-egg'),
          semantics: 'An egg, hatching',
        ),
      ];
    }
    final colour = def.color;
    final rows = renderBanner(daemonBanner, def.id);
    final card = _stage == HatchStage.card ? _card : null;
    final words =
        "fork() returned 0. it's a ${def.id}.\n"
        '${def.id} ${roster.rules.versions.first}: ${def.first}';
    return [
      if (pitch)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            'It is pitch black. You are likely to be eaten by a grue.',
            key: const ValueKey('daemon-hatch-pitch'),
            textAlign: TextAlign.center,
            style: DaemonInk.mono(size: 14, color: DaemonInk.dim, height: 1.4),
          ),
        ),
      if (_sprite != null)
        _art(
          _sprite!,
          DaemonInk.mono(
            size: 44,
            height: 1,
            weight: FontWeight.w600,
            color: _faint ? DaemonInk.ink.withValues(alpha: .35) : colour,
          ),
          key: const ValueKey('daemon-hatch-sprite'),
          semantics: _stage == HatchStage.silhouette
              ? 'A silhouette'
              : '${def.id} ${roster.rules.versions.first}',
        ),
      if (_bannerRows > 0) ...[
        const SizedBox(height: 18),
        _banner(rows, _bannerRows, def.id),
      ],
      if (_stage == HatchStage.card) ...[
        const SizedBox(height: 18),
        Text(
          rarityStamp(roster, def, shiny: _hatch?.shiny == true),
          key: const ValueKey('daemon-hatch-stamp'),
          textAlign: TextAlign.center,
          style: DaemonInk.mono(
            size: 13,
            color: DaemonInk.rarity(def.rarity),
          ).copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            words,
            key: const ValueKey('daemon-hatch-words'),
            textAlign: TextAlign.center,
            style: DaemonInk.mono(
              size: 13.5,
              color: DaemonInk.dim,
              height: 1.45,
            ),
          ),
        ),
        if (card != null) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pitch ? const Color(0xFF0C0C0C) : DaemonInk.ground,
              border: Border.all(color: DaemonInk.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _art(
              card.join('\n'),
              DaemonInk.mono(size: 12.5, color: DaemonInk.ink, height: 1.2),
              key: const ValueKey('daemon-hatch-card'),
              semantics: 'The card: ${def.id}, ${def.rarity}',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _button(
                'Share card',
                _share,
                key: const ValueKey('daemon-hatch-share'),
                hint: 'Copies the card as a code block',
                filled: true,
              ),
              _button('Done', _close, key: const ValueKey('daemon-hatch-done')),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _note ?? ' ',
              key: const ValueKey('daemon-hatch-note'),
              textAlign: TextAlign.center,
              style: DaemonInk.sans(size: 13.5, color: DaemonInk.dim),
            ),
          ),
        ],
      ],
    ];
  }

  Widget _button(
    String label,
    VoidCallback onPressed, {
    Key? key,
    String? hint,
    bool filled = false,
  }) => Semantics(
    hint: hint,
    child: TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(96, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        foregroundColor: filled ? DaemonInk.pitch : DaemonInk.ink,
        backgroundColor: filled ? DaemonInk.yellow : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: filled
              ? BorderSide.none
              : const BorderSide(color: DaemonInk.line),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFont.sans,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
