import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/creator.dart';
import '../models/map_cell.dart';
import '../services/creator_data_service.dart';

class MapViewer extends StatefulWidget {
  final MapLayout mapLayout;
  final ValueChanged<String?>? onBoothTap;

  const MapViewer({super.key, required this.mapLayout, this.onBoothTap});

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer>
    with SingleTickerProviderStateMixin {
  static const double _spatialCellSize = 96;
  static const double _legacyCellSize = 40;
  static const double _legacyRenderedBoothSize = 20;
  final TransformationController _transformationController =
      TransformationController();
  final Map<String, List<MapFeature>> _boothSpatialIndex = {};
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  MapFeature? _hoveredBooth;
  double _baseFontSize = 12;
  double _legacyToMapScale = 1;
  bool _hasBoothScaleReference = false;
  int _animationId = 0;

  bool get _isDesktop => MediaQuery.of(context).size.width > 768;

  @override
  void initState() {
    super.initState();
    _buildSpatialIndex();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CreatorDataProvider>().addListener(_onProviderChanged);
      _fitMap();
    });
  }

  @override
  void dispose() {
    try {
      context.read<CreatorDataProvider>().removeListener(_onProviderChanged);
    } catch (_) {
      // The provider may already be disposed during application shutdown.
    }
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mapLayout, widget.mapLayout)) {
      _buildSpatialIndex();
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    }
  }

  void _fitMap() {
    if (!mounted ||
        widget.mapLayout.width <= 0 ||
        widget.mapLayout.height <= 0) {
      return;
    }
    final viewport = context.size ?? MediaQuery.of(context).size;
    final scale = _initialScale(viewport);
    final x = (viewport.width - widget.mapLayout.width * scale) / 2;
    final y = (viewport.height - widget.mapLayout.height * scale) / 2;
    _transformationController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  double _initialScale(Size viewport) {
    if (_hasBoothScaleReference) {
      return ((_legacyRenderedBoothSize / _legacyCellSize) * _legacyToMapScale)
          .clamp(0.2, 1.5);
    }

    // Annotation-only maps have no booth scale to match, so fit them normally.
    return math
        .min(
          viewport.width / widget.mapLayout.width,
          viewport.height / widget.mapLayout.height,
        )
        .clamp(0.05, 1.25);
  }

  void _buildSpatialIndex() {
    _boothSpatialIndex.clear();
    _baseFontSize = _mapBaseFontSize(widget.mapLayout.features);
    final referenceBoothSize =
        _mapReferenceBoothSize(widget.mapLayout.features);
    _hasBoothScaleReference = referenceBoothSize != null;
    _legacyToMapScale =
        referenceBoothSize == null ? 1 : _legacyCellSize / referenceBoothSize;
    for (final feature
        in widget.mapLayout.features.where((item) => item.isBooth)) {
      final left = (feature.x / _spatialCellSize).floor();
      final right = (feature.right / _spatialCellSize).floor();
      final top = (feature.y / _spatialCellSize).floor();
      final bottom = (feature.bottom / _spatialCellSize).floor();
      for (var x = left; x <= right; x++) {
        for (var y = top; y <= bottom; y++) {
          (_boothSpatialIndex['$x,$y'] ??= []).add(feature);
        }
      }
    }
  }

  MapFeature? _findBoothAt(double x, double y) {
    final bucket = _boothSpatialIndex[
        '${(x / _spatialCellSize).floor()},${(y / _spatialCellSize).floor()}'];
    if (bucket == null) return null;
    for (final booth in bucket.reversed) {
      if (x >= booth.x &&
          x <= booth.right &&
          y >= booth.y &&
          y <= booth.bottom) {
        return booth;
      }
    }
    return null;
  }

  void _handleTap(TapUpDetails details) {
    if (widget.onBoothTap == null) return;
    final booth =
        _findBoothAt(details.localPosition.dx, details.localPosition.dy);
    widget.onBoothTap!(booth?.content);
  }

  void _handleHover(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) return;
    final booth = _findBoothAt(event.localPosition.dx, event.localPosition.dy);
    if (!identical(booth, _hoveredBooth)) setState(() => _hoveredBooth = booth);
  }

  void _handleExit(PointerEvent event) {
    if (_hoveredBooth != null) setState(() => _hoveredBooth = null);
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final creator = context.read<CreatorDataProvider>().selectedCreator;
    if (creator != null && creator.booths.isNotEmpty) {
      _centerOnBooths(creator.booths);
    }
  }

  void _centerOnBooths(List<String> boothIds) {
    final booths = widget.mapLayout.features
        .where(
            (feature) => feature.isBooth && boothIds.contains(feature.content))
        .toList();
    if (booths.isEmpty) return;

    _animationId++;
    final animationId = _animationId;
    _animationController.stop();
    _animation?.removeListener(_animationListener);
    final left = booths.map((item) => item.x).reduce(math.min);
    final right = booths.map((item) => item.right).reduce(math.max);
    final top = booths.map((item) => item.y).reduce(math.min);
    final bottom = booths.map((item) => item.bottom).reduce(math.max);

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || animationId != _animationId) return;
      final viewport = context.size ?? MediaQuery.of(context).size;
      final groupWidth = math.max(24.0, right - left);
      final groupHeight = math.max(24.0, bottom - top);
      final firstBoothId = booths.first.content;
      final sectionSeparator = firstBoothId.indexOf('-');
      final isMultiLetterSection = sectionSeparator > 1;
      final legacyFocusScale = isMultiLetterSection ? 0.6 : 0.8;
      final familiarFocusScale = legacyFocusScale * _legacyToMapScale;
      final groupFitScale = math.min(
        viewport.width * 0.62 / groupWidth,
        viewport.height * 0.46 / groupHeight,
      );
      // Match the old map's apparent booth size. Only zoom farther out when a
      // creator occupies booths too far apart to fit comfortably together.
      final targetScale =
          math.min(familiarFocusScale, groupFitScale).clamp(0.45, 6.0);
      final centerX = (left + right) / 2;
      final centerY = (top + bottom) / 2;
      final target = Matrix4.identity()
        ..translate(
          viewport.width / 2 - centerX * targetScale,
          viewport.height / (_isDesktop ? 2 : 3) - centerY * targetScale,
        )
        ..scale(targetScale);
      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: target,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutCubic,
      ));
      _animation!.addListener(_animationListener);
      _animationController.forward(from: 0);
    });
  }

  void _animationListener() {
    final animation = _animation;
    if (animation != null) _transformationController.value = animation.value;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CreatorDataProvider>();
    final selectedIds = provider.selectedCreator?.booths ?? const <String>[];
    final selectedFeatures = selectedIds.isEmpty
        ? const <MapFeature>[]
        : widget.mapLayout.features
            .where((feature) =>
                feature.isBooth && selectedIds.contains(feature.content))
            .toList(growable: false);
    final mapSize = Size(widget.mapLayout.width, widget.mapLayout.height);
    final mediaSize = MediaQuery.of(context).size;

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.04,
      maxScale: 8,
      boundaryMargin: EdgeInsets.only(
        left: mediaSize.width * 0.8,
        right: mediaSize.width * 0.8,
        top: mediaSize.height * 0.8,
        bottom: mediaSize.height * 0.8 +
            (!_isDesktop && provider.isCreatorCustomListMode ? 2000 : 0),
      ),
      constrained: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: MouseRegion(
          cursor: _hoveredBooth == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onHover: _handleHover,
          onExit: _handleExit,
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: mapSize,
                  painter: MapPainter(
                    features: widget.mapLayout.features,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    boothToCreators: provider.boothToCreators,
                    isCreatorCustomListMode: provider.isCreatorCustomListMode,
                    baseFontSize: _baseFontSize,
                  ),
                ),
              ),
              if (_hoveredBooth != null)
                RepaintBoundary(
                  child: CustomPaint(
                    size: mapSize,
                    painter: HoverOverlayPainter(
                      hoveredFeature: _hoveredBooth,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
              if (selectedFeatures.isNotEmpty)
                RepaintBoundary(
                  child: CustomPaint(
                    size: mapSize,
                    painter: SelectionOverlayPainter(
                      selectedFeatures: selectedFeatures,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                      baseFontSize: _baseFontSize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  final List<MapFeature> features;
  final bool isDark;
  final Color backgroundColor;
  final Map<String, List<Creator>>? boothToCreators;
  final bool isCreatorCustomListMode;
  final double baseFontSize;

  const MapPainter({
    required this.features,
    required this.isDark,
    required this.backgroundColor,
    required this.boothToCreators,
    required this.isCreatorCustomListMode,
    required this.baseFontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    for (final feature in features) {
      if (!feature.isBooth) _drawFeatureIfVisible(canvas, feature);
    }
    // Stored order is preserved within each tier. Booths stay above annotations,
    // while active booths are painted once more by the final selection overlay.
    for (final feature in features) {
      if (feature.isBooth) _drawFeatureIfVisible(canvas, feature);
    }
  }

  void _drawFeatureIfVisible(Canvas canvas, MapFeature feature) {
    if (feature.isEmpty) return;
    _drawFeature(
      canvas,
      feature,
      Rect.fromLTWH(feature.x, feature.y, feature.width, feature.height),
    );
  }

  void _drawFeature(Canvas canvas, MapFeature feature, Rect rect) {
    if (feature.isLineIndicator) {
      _drawLineIndicator(canvas, feature, rect);
      return;
    }
    if (feature.isText) {
      _drawLabel(canvas, feature, rect, _textFeatureColor(feature));
      return;
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = _fillColor(feature);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = feature.isBooth ? 1.25 : 1
      ..color = _borderColor(feature);
    final radius = Radius.circular(
      math.min(2.5, math.min(rect.width, rect.height) * 0.1),
    );

    if (feature.isArea) {
      canvas.drawRect(rect, fill);
      _drawDashedRect(canvas, rect, border);
    } else if (feature.isWall) {
      canvas.drawRect(rect, fill);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), border);
    }

    if (feature.content.isNotEmpty) {
      final textColor = feature.isSectionMarker || feature.isBoothSuffixMarker
          ? _textColor(feature)
          : feature.isHighlight
              ? const Color(0xFF111827)
              : feature.isArea
                  ? _featureColor(feature)
                  : _textColor(feature);
      _drawLabel(canvas, feature, rect, textColor);
    }
  }

  void _drawLineIndicator(Canvas canvas, MapFeature feature, Rect rect) {
    final start = Offset(
      rect.left + rect.width * (feature.lineStartX ?? 0),
      rect.top + rect.height * (feature.lineStartY ?? 0.5),
    );
    final end = Offset(
      rect.left + rect.width * (feature.lineEndX ?? 1),
      rect.top + rect.height * (feature.lineEndY ?? 0.5),
    );
    final color = feature.themeAware && feature.isWall
        ? (isDark ? const Color(0xFFE5E7EB) : const Color(0xFF111827))
        : _featureColor(feature);
    final strokeWidth = math.max(0.5, feature.thickness);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (!feature.isArrow) {
      canvas.drawLine(start, end, paint);
      return;
    }

    final delta = end - start;
    final length = delta.distance;
    if (length <= 0.1) return;
    final direction = delta / length;
    final headLength = math.min(length * 0.38, math.max(strokeWidth * 3, 8.0));
    final shaftEnd = end - direction * (headLength * 0.72);
    canvas.drawLine(start, shaftEnd, paint);
    final perpendicular = Offset(-direction.dy, direction.dx);
    final base = end - direction * headLength;
    final halfWidth = headLength * 0.52;
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          base.dx + perpendicular.dx * halfWidth,
          base.dy + perpendicular.dy * halfWidth,
        )
        ..lineTo(
          base.dx - perpendicular.dx * halfWidth,
          base.dy - perpendicular.dy * halfWidth,
        )
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  Color _fillColor(MapFeature feature) {
    if (feature.isSectionMarker) {
      return isDark ? const Color(0xFF5B4812) : const Color(0xFFFFD84D);
    }
    if (feature.isBoothSuffixMarker) {
      return isDark ? const Color(0xFF292331) : const Color(0xFFF0E8DE);
    }
    if (feature.isBooth) {
      if (boothToCreators?[feature.content]?.isEmpty ?? true) {
        return isDark ? const Color(0xFF292331) : const Color(0xFFF0E8DE);
      }
      if (isCreatorCustomListMode) return const Color(0xFFFF00BF);
      return _boothFillColor(_boothSection(feature.content));
    }
    if (feature.isHighlight) {
      return _featureColor(feature).withValues(alpha: 0.72);
    }
    if (feature.isArea) return _featureColor(feature).withValues(alpha: 0.04);
    if (feature.isWall) {
      return isDark ? const Color(0xFF09070D) : const Color(0xFF191522);
    }
    if (feature.isHall) return _featureColor(feature).withValues(alpha: 0.18);
    return isDark ? const Color(0xFF5B4812) : const Color(0xFFFFD84D);
  }

  Color _borderColor(MapFeature feature) {
    if (feature.isSectionMarker) {
      return isDark ? const Color(0xFFFF8A50) : const Color(0xFFE64A19);
    }
    if (feature.isBoothSuffixMarker) {
      return isDark ? const Color(0xFF4A4A4A) : const Color(0xFFBDBDBD);
    }
    if (feature.isBooth) {
      if (boothToCreators?[feature.content]?.isEmpty ?? true) {
        return isDark ? const Color(0xFF4A4A4A) : const Color(0xFFBDBDBD);
      }
      if (isCreatorCustomListMode) return const Color(0xFFFF88CD);
      return _boothBorderColor(_boothSection(feature.content));
    }
    if (feature.isWall) {
      return isDark ? const Color(0xFF2A2A2A) : const Color(0xFF616161);
    }
    return _featureColor(feature);
  }

  Color _textColor(MapFeature feature) {
    if (feature.isSectionMarker) {
      return isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    }
    if (feature.isBoothSuffixMarker) {
      return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }
    if (feature.isBooth) {
      if (boothToCreators?[feature.content]?.isEmpty ?? true) {
        return isDark ? Colors.grey.shade400 : Colors.grey.shade700;
      }
      return isCreatorCustomListMode || isDark
          ? Colors.white
          : const Color(0xFF191522);
    }
    return isDark ? Colors.grey.shade300 : Colors.grey.shade800;
  }

  void _drawLabel(Canvas canvas, MapFeature feature, Rect rect, Color color) {
    final text = _displayText(feature);
    if (text.isEmpty || rect.width < 3 || rect.height < 3) return;
    final rotated = feature.rotation.abs() == 90;
    final availableWidth = rotated ? rect.height : rect.width;
    final availableHeight = rotated ? rect.width : rect.height;
    final fontSize = _featureLabelFontSize(
      feature,
      text,
      availableWidth,
      availableHeight,
      baseFontSize,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: fontSize,
          height: 1,
          fontWeight: feature.isBooth || feature.isHighlight
              ? FontWeight.w700
              : FontWeight.w500,
          color: color,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: availableWidth);
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (feature.rotation != 0) {
      canvas.rotate(feature.rotation * math.pi / 180);
    }
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  String _displayText(MapFeature feature) {
    return feature.displayLabel;
  }

  Color _featureColor(MapFeature feature) =>
      _parseHexColor(feature.color) ??
      (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));

  Color _textFeatureColor(MapFeature feature) {
    if (feature.themeAware) {
      return isDark ? const Color(0xFFF4F6FA) : const Color(0xFF111827);
    }
    return _featureColor(feature);
  }

  String _boothSection(String id) {
    final separator = id.indexOf('-');
    return separator > 0
        ? id.substring(0, separator).toUpperCase()
        : 'CORPORATE';
  }

  Color _boothFillColor(String section) {
    const light = [
      Color(0xFFFFD9E8),
      Color(0xFFC9F7FC),
      Color(0xFFFFE99A),
      Color(0xFFE6E0FF),
      Color(0xFFFFD9C8),
      Color(0xFFD5F4DF),
      Color(0xFFFFE0F1),
      Color(0xFFD8E8FF),
    ];
    const dark = [
      Color(0xFF652443),
      Color(0xFF12505A),
      Color(0xFF65531C),
      Color(0xFF43366F),
      Color(0xFF693523),
      Color(0xFF24553A),
      Color(0xFF5E294E),
      Color(0xFF29456B),
    ];
    final palette = isDark ? dark : light;
    final hash = section.codeUnits.fold(0, (sum, value) => sum + value);
    return palette[hash % palette.length];
  }

  Color _boothBorderColor(String section) {
    const colors = [
      Color(0xFFFF3D8D),
      Color(0xFF009FB2),
      Color(0xFFC39200),
      Color(0xFF7657FF),
      Color(0xFFE25B31),
      Color(0xFF218C52),
      Color(0xFFD63A91),
      Color(0xFF3775CC),
    ];
    final hash = section.codeUnits.fold(0, (sum, value) => sum + value);
    return colors[hash % colors.length];
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 8, metric.length)),
          paint,
        );
        distance += 13;
      }
    }
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) =>
      oldDelegate.features != features ||
      oldDelegate.isDark != isDark ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.boothToCreators != boothToCreators ||
      oldDelegate.isCreatorCustomListMode != isCreatorCustomListMode ||
      oldDelegate.baseFontSize != baseFontSize;
}

class HoverOverlayPainter extends CustomPainter {
  final MapFeature? hoveredFeature;
  final bool isDark;

  const HoverOverlayPainter(
      {required this.hoveredFeature, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final feature = hoveredFeature;
    if (feature == null) return;
    final rect =
        Rect.fromLTWH(feature.x, feature.y, feature.width, feature.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()
        ..color = isDark ? const Color(0x5926DDF0) : const Color(0x6600C8E0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = isDark ? const Color(0xFF26DDF0) : const Color(0xFF008DA0),
    );
  }

  @override
  bool shouldRepaint(HoverOverlayPainter oldDelegate) =>
      oldDelegate.hoveredFeature != hoveredFeature ||
      oldDelegate.isDark != isDark;
}

class SelectionOverlayPainter extends CustomPainter {
  final List<MapFeature> selectedFeatures;
  final bool isDark;
  final double baseFontSize;

  const SelectionOverlayPainter({
    required this.selectedFeatures,
    required this.isDark,
    required this.baseFontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final feature in selectedFeatures) {
      final rect =
          Rect.fromLTWH(feature.x, feature.y, feature.width, feature.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = isDark ? const Color(0xFFFFDC60) : const Color(0xFFFF3D8D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = isDark ? const Color(0xFFFF5CA2) : const Color(0xFF191522),
      );
      _drawLabel(canvas, feature, rect);
    }
  }

  void _drawLabel(Canvas canvas, MapFeature feature, Rect rect) {
    final text = feature.displayLabel;
    if (text.isEmpty) return;
    final fontSize = _featureLabelFontSize(
      feature,
      text,
      rect.width,
      rect.height,
      baseFontSize,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.black : Colors.white,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(SelectionOverlayPainter oldDelegate) =>
      oldDelegate.selectedFeatures != selectedFeatures ||
      oldDelegate.isDark != isDark ||
      oldDelegate.baseFontSize != baseFontSize;
}

Color? _parseHexColor(String? value) {
  if (value == null) return null;
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length != 6 && normalized.length != 8) return null;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

double _featureLabelFontSize(
  MapFeature feature,
  String text,
  double availableWidth,
  double availableHeight,
  double baseFontSize,
) {
  final isCorporateBooth = feature.isBooth && !feature.content.contains('-');
  final heightFactor = feature.isText
      ? 0.52
      : isCorporateBooth
          ? 0.30
          : 0.42;
  final characterWidth = isCorporateBooth ? 0.70 : 0.58;
  final naturalSize = math
      .max(
        3,
        math.min(
          availableHeight * heightFactor,
          availableWidth / math.max(1.0, text.length * characterWidth),
        ),
      )
      .toDouble();
  final categoryMaximum = feature.isBooth
      ? baseFontSize * 1.35
      : feature.isText
          ? baseFontSize * 2.25
          : feature.isArea
              ? baseFontSize * 1.8
              : feature.isBoothSuffixMarker
                  ? baseFontSize * 0.8
                  : feature.isHighlight
                      ? baseFontSize * 1.3
                      : baseFontSize * 1.5;
  final requested = feature.fontSize != null && feature.fontSize! > 0
      ? feature.fontSize!
      : math.min(naturalSize, categoryMaximum);
  return math
      .max(
        3,
        math.min(
          requested,
          math.min(
            availableHeight * 0.9,
            availableWidth / math.max(1.0, text.length * 0.52),
          ),
        ),
      )
      .toDouble();
}

double _mapBaseFontSize(List<MapFeature> features) {
  final referenceBoothSize = _mapReferenceBoothSize(features);
  if (referenceBoothSize == null) return 12;
  return (referenceBoothSize * 0.8).clamp(6, 18);
}

double? _mapReferenceBoothSize(List<MapFeature> features) {
  final boothSizes = features
      .where((feature) => feature.isBooth && feature.content.contains('-'))
      .map((feature) => math.sqrt(feature.width * feature.height))
      .where((size) => size > 0)
      .toList()
    ..sort();
  if (boothSizes.isEmpty) {
    boothSizes.addAll(
      features
          .where((feature) => feature.isBooth)
          .map((feature) => math.sqrt(feature.width * feature.height))
          .where((size) => size > 0),
    );
    boothSizes.sort();
  }
  if (boothSizes.isEmpty) return null;
  return boothSizes[boothSizes.length ~/ 2];
}
