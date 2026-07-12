import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../theme/app_theme.dart';

/// A single grid cell for a photo/video asset — thumbnail, rounded corners,
/// a video-duration badge, a fade-in entrance, and a Hero tag so tapping it
/// animates smoothly into the fullscreen viewer.
class MediaTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;
  final String heroTag;

  const MediaTile({
    super.key,
    required this.asset,
    required this.onTap,
    required this.heroTag,
  });

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.surface),
            Hero(
              tag: heroTag,
              child: AssetEntityImage(
                asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(300),
                fit: BoxFit.cover,
              ),
            ),
            if (asset.type == AssetType.video)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(asset.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
