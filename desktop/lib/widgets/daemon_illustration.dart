import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../daemons/illustrated_art.dart';

/// A bounded bitmap view. Small chrome decodes the 64px assets; only portraits
/// use the 350px originals. The frame timer repaints this boundary alone and
/// stops for Reduce Motion, background tabs, and static card/slot renders.
class DaemonIllustration extends StatefulWidget {
  const DaemonIllustration({
    super.key,
    required this.art,
    this.size = 350,
    this.frame = 0,
    this.animate = false,
    this.silhouette,
    this.semanticsLabel,
  });

  final IllustratedArt art;
  final double size;
  final int frame;
  final bool animate;
  final Color? silhouette;
  final String? semanticsLabel;

  @override
  State<DaemonIllustration> createState() => _DaemonIllustrationState();
}

class _DaemonIllustrationState extends State<DaemonIllustration> {
  Timer? _timer;
  int _tick = 0;

  bool get _moving =>
      widget.animate &&
      widget.art.frames > 1 &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(DaemonIllustration old) {
    super.didUpdateWidget(old);
    if (old.art.stem != widget.art.stem) _tick = 0;
    _schedule();
  }

  void _schedule() {
    if (_moving == (_timer != null)) return;
    _timer?.cancel();
    _timer = null;
    _tick = 0;
    if (_moving) {
      _timer = Timer.periodic(const Duration(milliseconds: 190), (_) {
        if (mounted) setState(() => _tick++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = widget.size <= 64;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final frame = reduced ? 0 : widget.frame + _tick;
    final center = widget.art.center(slot: small);
    final sourceSize = small ? 64 : 350;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: Transform.translate(
          offset: Offset(
            (.5 - center.$1 / sourceSize) * widget.size,
            (.5 - center.$2 / sourceSize) * widget.size,
          ),
          child: Image.asset(
            widget.art.asset(frame, slot: small),
            key: ValueKey(widget.art.stem),
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // Never decode an upscaled copy of the source bitmap.
            cacheWidth: math.min(
              small ? 64 : 350,
              (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil(),
            ),
            gaplessPlayback: true,
            color: widget.silhouette,
            colorBlendMode: widget.silhouette == null ? null : BlendMode.srcIn,
            semanticLabel: widget.semanticsLabel,
            excludeFromSemantics: widget.semanticsLabel == null,
          ),
        ),
      ),
    );
  }
}
