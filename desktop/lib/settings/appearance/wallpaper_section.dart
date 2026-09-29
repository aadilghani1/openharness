import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/appearance_prefs_store.dart';
import '../../shared/theme/harness_background.dart';
import '../../widgets/swarm_wallpaper.dart';

class WallpaperSection extends StatelessWidget {
  const WallpaperSection({super.key, this.store});
  final AppearancePrefsStore? store;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final prefs = store ?? appearancePrefsStore;
    return ValueListenableBuilder<AppearancePrefs>(
      valueListenable: prefs,
      builder: (context, value, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wallpaper',
            style: grid.AppType.heading(color: grid.AppPalette.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'A little curiosity for your new tabs.',
            style: grid.AppType.body(color: grid.AppPalette.textSecondary),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >=
                      300 * math.max(1, grid.appTextScaleOf(context))
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final choice in HarnessBackground.gallery)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        button: true,
                        selected: value.background == choice,
                        label: '${choice.label} wallpaper',
                        onTap: () => prefs.setBackground(choice),
                        child: ExcludeSemantics(
                          child: Material(
                            color: Colors.transparent,
                            child: TextButton(
                              key: ValueKey('wallpaper-${choice.name}'),
                              onPressed: () => prefs.setBackground(choice),
                              style:
                                  TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ).copyWith(
                                    side: WidgetStateProperty.resolveWith(
                                      (states) => BorderSide(
                                        width:
                                            MediaQuery.highContrastOf(context)
                                            ? 2
                                            : 1.5,
                                        color:
                                            states.contains(WidgetState.focused)
                                            ? grid.AppPalette.accentOnSurface
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: value.background == choice
                                              ? grid.AppPalette.swarmAccent
                                              : grid.AppPalette.divider,
                                          width: 2,
                                        ),
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            SwarmWallpaper(
                                              background: choice,
                                              thumbnail: true,
                                            ),
                                            if (value.background == choice)
                                              const Positioned(
                                                right: 8,
                                                bottom: 8,
                                                child: Icon(
                                                  Icons.check_circle,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      choice.label,
                                      style: grid.AppType.label(
                                        color: grid.AppPalette.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
