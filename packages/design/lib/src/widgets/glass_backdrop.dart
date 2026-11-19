import 'package:flutter/material.dart';

import '../theme/glass_settings.dart';

/// Kos TV: the bloom field behind the glass theme. It used to drift on a 16
/// second loop, which redrew the whole stack every frame; it stays still on
/// every tier now, so the animation is gone.
class GlassBackdrop extends StatelessWidget {
  // Not const on purpose: it reads GlassSettings in build, and a const
  // instance would be skipped when the shell rebuilds after a quality step.
  // ignore: prefer_const_constructors_in_immutables
  GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    // The sheen tier collapses the bloom stack (base fill, three radial
    // gradients, veil, and darkening gradient) into a single gradient pass.
    // Six full-screen draws per frame are too expensive for the TV boxes and
    // web renderers that resolve to sheen, and Impeller re-renders them every
    // frame because it has no raster cache. The same collapse applies when
    // the adaptive glass scope has throttled to minimal quality, since a
    // device under pressure shouldn't pay for the bloom stack either.
    if (GlassSettings.cheapBackdrop) {
      return const RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              stops: [0.0, 0.55, 1.0],
              colors: [
                Color(0xFF16395E),
                Color(0xFF0B0F17),
                Color(0xFF241E42),
              ],
            ),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          final r1 = shortest > 0 ? 1100 / shortest : 1.0;
          final r2 = shortest > 0 ? 1000 / shortest : 1.0;
          final r3 = shortest > 0 ? 900 / shortest : 1.0;

          final bloomField = RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF05080F)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: r1,
                      colors: const [Color(0x8C0A85FF), Color(0x000A85FF)],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.bottomLeft,
                      radius: r2,
                      colors: const [Color(0x6B7D59F2), Color(0x007D59F2)],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: r3,
                      colors: const [Color(0x4700C7C7), Color(0x0000C7C7)],
                    ),
                  ),
                ),
              ],
            ),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              bloomField,
              const Positioned.fill(
                child: ColoredBox(color: Color(0x33FFFFFF)),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x38000000), Color(0x80000000)],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
