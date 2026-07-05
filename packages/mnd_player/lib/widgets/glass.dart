import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mnd_player/utils/platform_performance.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blurSigma;
  final Color tintColor;
  final Color borderColor;
  final List<BoxShadow> shadows;
  final bool enableBlur;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = const EdgeInsets.all(0),
    this.blurSigma = 6,
    this.tintColor = const Color(0x1AFFFFFF),
    this.borderColor = const Color(0x33FFFFFF),
    this.shadows = const [],
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return RepaintBoundary(
      child: FutureBuilder<bool>(
        future: PlatformPerformance.instance.shouldDisableBlur(),
        initialData: false,
        builder: (context, snapshot) {
          final shouldDisableBlur = snapshot.data ?? false;
          final effectiveBlur = (enableBlur && !shouldDisableBlur)
              ? blurSigma
              : 0.0;

          // Если blur отключен, используем более непрозрачный фон
          final effectiveTint = effectiveBlur == 0.0
              ? tintColor.withOpacity((tintColor.opacity * 2).clamp(0.0, 1.0))
              : tintColor;

          return Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: effectiveBlur > 0 ? shadows : [],
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: effectiveBlur > 0
                  ? BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: effectiveBlur,
                        sigmaY: effectiveBlur,
                      ),
                      child: _buildContent(effectiveTint, borderRadius),
                    )
                  : _buildContent(effectiveTint, borderRadius),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(Color tint, BorderRadius borderRadius) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
