import 'dart:io';
import 'dart:ui' as ui;

import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/utils/file_storage.dart';
import 'package:flutter/material.dart';

class ModuleAssetFrame extends StatelessWidget {
  final String questId;
  final ButtonStyleConfig style;
  final double module;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final BoxConstraints constraints;
  final Widget child;

  const ModuleAssetFrame({
    super.key,
    required this.questId,
    required this.style,
    required this.module,
    required this.onTap,
    required this.padding,
    required this.constraints,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((module * 0.6).clamp(8.0, 20.0));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: constraints,
          child: Stack(
            children: [
              ModuleAssetLayer(
                questId: questId,
                style: style,
                module: module,
                fallbackColor: style.fillColor.withOpacity(0.92),
              ),
              Padding(
                padding: padding,
                child: Center(child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModuleAssetLayer extends StatelessWidget {
  final String questId;
  final ButtonStyleConfig style;
  final double module;
  final Color fallbackColor;

  const ModuleAssetLayer({
    super.key,
    required this.questId,
    required this.style,
    required this.module,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final edge = module;
    return Stack(
      children: [
        Positioned(
          left: edge,
          right: edge,
          top: edge,
          bottom: edge,
          child: _TiledImageBox(
            questId: questId,
            path: style.centerAsset!,
            tileSize: module,
            repeatX: true,
            repeatY: true,
            fallbackColor: fallbackColor,
          ),
        ),
        Positioned(
          left: edge,
          right: edge,
          top: 0,
          height: module,
          child: _TiledImageBox(
            questId: questId,
            path: style.hAsset!,
            tileSize: module,
            repeatX: true,
            repeatY: false,
            fallbackColor: Colors.transparent,
          ),
        ),
        Positioned(
          left: edge,
          right: edge,
          bottom: 0,
          height: module,
          child: RotatedBox(
            quarterTurns: 2,
            child: _TiledImageBox(
              questId: questId,
              path: style.hAsset!,
              tileSize: module,
              repeatX: true,
              repeatY: false,
              fallbackColor: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          top: edge,
          bottom: edge,
          left: 0,
          width: module,
          child: _TiledImageBox(
            questId: questId,
            path: style.vAsset!,
            tileSize: module,
            repeatX: false,
            repeatY: true,
            fallbackColor: Colors.transparent,
          ),
        ),
        Positioned(
          top: edge,
          bottom: edge,
          right: 0,
          width: module,
          child: RotatedBox(
            quarterTurns: 2,
            child: _TiledImageBox(
              questId: questId,
              path: style.vAsset!,
              tileSize: module,
              repeatX: false,
              repeatY: true,
              fallbackColor: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          width: module,
          height: module,
          child: _TiledImageBox(
            questId: questId,
            path: style.cornerAsset!,
            tileSize: module,
            repeatX: false,
            repeatY: false,
            fallbackColor: Colors.transparent,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          width: module,
          height: module,
          child: RotatedBox(
            quarterTurns: 1,
            child: _TiledImageBox(
              questId: questId,
              path: style.cornerAsset!,
              tileSize: module,
              repeatX: false,
              repeatY: false,
              fallbackColor: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: module,
          height: module,
          child: RotatedBox(
            quarterTurns: 3,
            child: _TiledImageBox(
              questId: questId,
              path: style.cornerAsset!,
              tileSize: module,
              repeatX: false,
              repeatY: false,
              fallbackColor: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          width: module,
          height: module,
          child: RotatedBox(
            quarterTurns: 2,
            child: _TiledImageBox(
              questId: questId,
              path: style.cornerAsset!,
              tileSize: module,
              repeatX: false,
              repeatY: false,
              fallbackColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

class _TiledImageBox extends StatefulWidget {
  final String questId;
  final String path;
  final double tileSize;
  final bool repeatX;
  final bool repeatY;
  final Color fallbackColor;

  const _TiledImageBox({
    required this.questId,
    required this.path,
    required this.tileSize,
    required this.repeatX,
    required this.repeatY,
    required this.fallbackColor,
  });

  @override
  State<_TiledImageBox> createState() => _TiledImageBoxState();
}

class _TiledImageBoxState extends State<_TiledImageBox> {
  ui.Image? _image;
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TiledImageBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.questId != widget.questId) {
      _load();
    }
  }

  Future<void> _load() async {
    final resolved = widget.path.startsWith('quests/')
        ? widget.path
        : 'quests/${widget.questId}/${widget.path}';
    final path = await FileStorage.getFilePath(resolved);
    if (!mounted) return;
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() {
        _resolvedPath = null;
        _image = null;
      });
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final img = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() {
        _resolvedPath = path;
        _image = img;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvedPath = path;
        _image = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null || _resolvedPath == null) {
      return ColoredBox(color: widget.fallbackColor);
    }
    return CustomPaint(
      painter: _TiledImagePainter(
        image: _image!,
        tileSize: widget.tileSize,
        repeatX: widget.repeatX,
        repeatY: widget.repeatY,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TiledImagePainter extends CustomPainter {
  final ui.Image image;
  final double tileSize;
  final bool repeatX;
  final bool repeatY;

  _TiledImagePainter({
    required this.image,
    required this.tileSize,
    required this.repeatX,
    required this.repeatY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = tileSize / image.width;
    final scaleY = tileSize / image.height;

    if (!repeatX && !repeatY) {
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      final paint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false;
      canvas.drawImageRect(image, src, dst, paint);
      return;
    }

    final tileModeX = repeatX ? TileMode.repeated : TileMode.clamp;
    final tileModeY = repeatY ? TileMode.repeated : TileMode.clamp;
    final matrix = Matrix4.identity()..scale(scaleX, scaleY);
    final shader = ImageShader(image, tileModeX, tileModeY, matrix.storage);
    final paint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _TiledImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.tileSize != tileSize ||
        oldDelegate.repeatX != repeatX ||
        oldDelegate.repeatY != repeatY;
  }
}
