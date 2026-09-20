import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/map_cell.dart';

class MapParser {
  static const double legacyCellSize = 40;

  static Future<MapLayout> loadMapLayout() async {
    final jsonString = await rootBundle.loadString('data/map.json');
    return parseMapLayout(json.decode(jsonString));
  }

  static MapLayout parseMapLayout(Object? jsonData) {
    if (jsonData is Map<String, dynamic> && jsonData['features'] is List) {
      return _parseSemanticMap(jsonData);
    }
    if (jsonData is List) {
      final grid = jsonData
          .map<List<String>>((row) => (row as List<dynamic>)
              .map<String>((cell) => cell?.toString() ?? '')
              .toList())
          .toList();
      return _legacyLayout(grid);
    }
    throw const FormatException('Unsupported map JSON format');
  }

  static MapLayout _parseSemanticMap(Map<String, dynamic> document) {
    final bounds = document['bounds'];
    if (bounds is! Map<String, dynamic>) {
      throw const FormatException('Semantic map is missing bounds');
    }
    final width = (bounds['width'] as num?)?.toDouble();
    final height = (bounds['height'] as num?)?.toDouble();
    if (width == null || height == null || width <= 0 || height <= 0) {
      throw const FormatException('Semantic map has invalid bounds');
    }

    final features = <MapFeature>[];
    final rawFeatures = document['features'] as List<dynamic>;
    for (var index = 0; index < rawFeatures.length; index++) {
      final raw = rawFeatures[index];
      if (raw is! Map<String, dynamic> || raw['status'] == 'suggestion') {
        continue;
      }
      final geometry = raw['geometry'];
      if (geometry is! Map<String, dynamic> || geometry['type'] != 'rect') {
        continue;
      }
      final x = (geometry['x'] as num?)?.toDouble();
      final y = (geometry['y'] as num?)?.toDouble();
      final featureWidth = (geometry['width'] as num?)?.toDouble();
      final featureHeight = (geometry['height'] as num?)?.toDouble();
      if (x == null ||
          y == null ||
          featureWidth == null ||
          featureHeight == null ||
          featureWidth <= 0 ||
          featureHeight <= 0) continue;
      final kind = raw['kind']?.toString() ?? 'booth';
      final lineStart = raw['lineStart'];
      final lineEnd = raw['lineEnd'];
      final content = kind == 'booth'
          ? (raw['id']?.toString() ?? '')
          : (raw['label']?.toString() ?? '');
      features.add(MapFeature(
        uid: raw['uid']?.toString() ?? 'feature-$index',
        content: content,
        kind: kind,
        type: raw['type']?.toString(),
        x: x,
        y: y,
        width: featureWidth,
        height: featureHeight,
        color: raw['color']?.toString(),
        rotation: (raw['rotation'] as num?)?.toDouble() ?? 0,
        thickness: (raw['thickness'] as num?)?.toDouble() ?? 1,
        lineStartX: lineStart is Map<String, dynamic>
            ? (lineStart['x'] as num?)?.toDouble()
            : null,
        lineStartY: lineStart is Map<String, dynamic>
            ? (lineStart['y'] as num?)?.toDouble()
            : null,
        lineEndX: lineEnd is Map<String, dynamic>
            ? (lineEnd['x'] as num?)?.toDouble()
            : null,
        lineEndY: lineEnd is Map<String, dynamic>
            ? (lineEnd['y'] as num?)?.toDouble()
            : null,
        themeAware: (raw['themeAware'] as bool?) ?? kind == 'text',
        fontSize: (raw['fontSize'] as num?)?.toDouble(),
      ));
    }

    return MapLayout(
      features: features,
      width: width,
      height: height,
      schemaVersion: (document['schemaVersion'] as num?)?.toInt() ?? 2,
    );
  }

  static MapLayout _legacyLayout(List<List<String>> grid) {
    final merged = mergeCells(grid);
    final features = merged.where((cell) => !cell.isEmpty).map((cell) {
      final kind = cell.isBooth
          ? 'booth'
          : cell.isWall
              ? 'wall'
              : cell.isHall
                  ? 'hall'
                  : 'marker';
      return MapFeature(
        uid: 'legacy-${cell.startRow}-${cell.startCol}',
        content: cell.content,
        kind: kind,
        x: cell.startCol * legacyCellSize,
        y: cell.startRow * legacyCellSize,
        width: cell.colSpan * legacyCellSize,
        height: cell.rowSpan * legacyCellSize,
      );
    }).toList(growable: false);
    return MapLayout(
      features: features,
      width: (grid.isEmpty ? 0 : grid[0].length) * legacyCellSize,
      height: grid.length * legacyCellSize,
      schemaVersion: 1,
    );
  }

  static List<MergedCell> mergeCells(List<List<String>> grid) {
    final int rows = grid.length;
    final int cols = grid.isEmpty ? 0 : grid[0].length;

    // Track which cells have been merged
    final processed =
        List.generate(rows, (_) => List.generate(cols, (_) => false));
    final List<MergedCell> mergedCells = [];

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (processed[r][c]) continue;

        final content = grid[r][c].trim();

        // Find the extent of this merged cell
        int rowSpan = 1;
        int colSpan = 1;

        // Check how far right we can extend
        while (c + colSpan < cols &&
            !processed[r][c + colSpan] &&
            grid[r][c + colSpan].trim() == content) {
          colSpan++;
        }

        // Check how far down we can extend (for each column in the span)
        bool canExtendDown = true;
        while (canExtendDown && r + rowSpan < rows) {
          for (int dc = 0; dc < colSpan; dc++) {
            if (processed[r + rowSpan][c + dc] ||
                grid[r + rowSpan][c + dc].trim() != content) {
              canExtendDown = false;
              break;
            }
          }
          if (canExtendDown) rowSpan++;
        }

        // Mark all cells in this merged area as processed
        for (int dr = 0; dr < rowSpan; dr++) {
          for (int dc = 0; dc < colSpan; dc++) {
            processed[r + dr][c + dc] = true;
          }
        }

        // Create merged cell
        mergedCells.add(MergedCell(
          content: content,
          startRow: r,
          startCol: c,
          rowSpan: rowSpan,
          colSpan: colSpan,
        ));
      }
    }

    return mergedCells;
  }
}
