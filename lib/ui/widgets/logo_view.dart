import 'baked_logo_shadow.dart';
import 'offline_aware_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// A logo display widget with a drop shadow that follows the image shape.
class LogoView extends StatelessWidget {
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final double maxHeight;
  final double maxWidth;

  const LogoView({
    super.key,
    this.imageUrl,
    this.imageProvider,
    this.maxHeight = 80,
    this.maxWidth = 200,
  });

  ImageProvider? get _effectiveProvider {
    if (imageProvider != null) return imageProvider;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return offlineAwareImageProvider(imageUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _effectiveProvider;
    if (provider == null) return const SizedBox.shrink();

    final image = Image(
      image: provider,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        maxWidth: maxWidth,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Kos TV: blurred once when the logo loads, over the same box as
          // the logo, rather than by a live blur on every frame.
          Positioned.fill(
            child: BakedLogoShadow(
              image: provider,
              color: AppColorScheme.scrim.withValues(alpha: 0.6),
            ),
          ),
          image,
        ],
      ),
    );
  }
}
