import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Soft, blurred gradient blobs on a dark canvas — the backdrop that makes
/// translucent "glass" surfaces elsewhere in the app actually look frosted
/// rather than just dimmed. Painted once behind the bottom-nav shell so it
/// shows through every tab's now-transparent Scaffold.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          _blob(top: -80, left: -60, size: 260, color: AppColors.accent.withOpacity(0.35)),
          _blob(top: 160, right: -100, size: 240, color: AppColors.studyAmber.withOpacity(0.22)),
          _blob(bottom: -60, left: 40, size: 280, color: AppColors.studyGreen.withOpacity(0.18)),
        ],
      ),
    );
  }

  Widget _blob({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

/// Frosted panel primitive — blurred backdrop + translucent tint + subtle
/// border. Use in place of a plain `Container` wherever a "glass" surface
/// is wanted over the [GlassBackground].
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = AppRadius.md,
    this.padding,
    this.margin,
    this.color,
    this.blurSigma = 20,
    this.enableBlur = true,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double blurSigma;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: child,
    );
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: content,
              )
            : content,
      ),
    );
  }
}
