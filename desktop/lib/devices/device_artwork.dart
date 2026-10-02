import 'package:flutter/material.dart';

/// Product photography from autonomous.ai/harness-device. Bundled so the
/// library remains useful when the computer is offline.
class DeviceArtwork extends StatelessWidget {
  const DeviceArtwork({
    super.key,
    this.desk = false,
    this.side = false,
    this.closeUp = false,
  });
  final bool desk, side, closeUp;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: Transform.scale(
        scale: closeUp ? 1.85 : 1,
        alignment: const Alignment(-.22, .12),
        child: Image.asset(
          'assets/devices/harness-${desk
              ? 'desk'
              : side
              ? 'side'
              : 'front'}.webp',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: const Alignment(-.22, .12),
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
