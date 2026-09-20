class MapCell {
  final String content;
  final int row;
  final int col;
  final bool isEmpty;
  final bool isBooth;
  final bool isLocationMarker;
  final bool isWall;
  final bool isHall;

  MapCell({
    required this.content,
    required this.row,
    required this.col,
  })  : isEmpty = content.trim().isEmpty,
        isBooth = _isBooth(content),
        isLocationMarker = _isLocationMarker(content),
        isWall = _isWall(content),
        isHall = _isHall(content);

  static bool _isBooth(String content) {
    if (content.trim().isEmpty) return false;
    // Sectioned booths (R-12b) and sectionless corporate booths (1207).
    return RegExp(r'^(?:[A-Z]+-)?\d+[a-z]?$', caseSensitive: false)
        .hasMatch(content.trim());
  }

  static bool _isLocationMarker(String content) {
    if (content.trim().isEmpty) return false;
    // Location markers are single/double letters or just "a" or "b"
    return !_isBooth(content) &&
        !_isWall(content) &&
        !_isHall(content) &&
        content.trim().isNotEmpty;
  }

  static bool _isWall(String content) {
    if (content.trim().isEmpty) return false;
    // Wall cells are marked with "X"
    return content.trim() == 'X';
  }

  static bool _isHall(String content) {
    if (content.trim().isEmpty) return false;
    // Hall cells are marked with "HALL X" where X is a number
    return RegExp(r'^HALL\s+\d+$', caseSensitive: false)
        .hasMatch(content.trim());
  }

  @override
  String toString() => 'MapCell($content at [$row,$col])';
}

class MapFeature {
  final String uid;
  final String content;
  final String kind;
  final String? type;
  final double x;
  final double y;
  final double width;
  final double height;
  final String? color;
  final double rotation;
  final double thickness;
  final double? lineStartX;
  final double? lineStartY;
  final double? lineEndX;
  final double? lineEndY;
  final bool themeAware;
  final double? fontSize;

  const MapFeature({
    required this.uid,
    required this.content,
    required this.kind,
    this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.color,
    this.rotation = 0,
    this.thickness = 1,
    this.lineStartX,
    this.lineStartY,
    this.lineEndX,
    this.lineEndY,
    this.themeAware = false,
    this.fontSize,
  });

  bool get isBooth => kind == 'booth';
  bool get isHighlight => kind == 'highlight';
  bool get isSectionMarker => isHighlight && type == 'section-marker';
  bool get isBoothSuffixMarker => isHighlight && type == 'booth-suffix-marker';
  bool get isArea => kind == 'area';
  bool get isText => kind == 'text';
  bool get isWall => kind == 'wall';
  bool get isArrow => kind == 'arrow';
  bool get isLineIndicator =>
      isArrow ||
      (isWall &&
          lineStartX != null &&
          lineStartY != null &&
          lineEndX != null &&
          lineEndY != null);
  bool get isHall => kind == 'hall';
  bool get isEmpty =>
      content.trim().isEmpty && !isArea && !isHighlight && !isLineIndicator;
  bool get isLocationMarker =>
      !isBooth && !isWall && !isHall && !isArea && !isText;

  String get displayLabel {
    if (!isBooth) return content;
    final separator = content.indexOf('-');
    final boothPart =
        separator >= 0 ? content.substring(separator + 1) : content;
    if (boothPart.length < 2) return boothPart;
    final suffix = boothPart.codeUnitAt(boothPart.length - 1) | 0x20;
    final number = boothPart.substring(0, boothPart.length - 1);
    return (suffix == 0x61 || suffix == 0x62) && int.tryParse(number) != null
        ? number
        : boothPart;
  }

  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
}

class MapLayout {
  final List<MapFeature> features;
  final double width;
  final double height;
  final int schemaVersion;

  const MapLayout({
    required this.features,
    required this.width,
    required this.height,
    required this.schemaVersion,
  });
}

class MergedCell {
  final String content;
  final int startRow;
  final int startCol;
  final int rowSpan;
  final int colSpan;
  final bool isEmpty;
  final bool isBooth;
  final bool isLocationMarker;
  final bool isWall;
  final bool isHall;

  MergedCell({
    required this.content,
    required this.startRow,
    required this.startCol,
    required this.rowSpan,
    required this.colSpan,
  })  : isEmpty = content.trim().isEmpty,
        isBooth = MapCell._isBooth(content),
        isLocationMarker = MapCell._isLocationMarker(content),
        isWall = MapCell._isWall(content),
        isHall = MapCell._isHall(content);

  bool containsPosition(int row, int col) {
    return row >= startRow &&
        row < startRow + rowSpan &&
        col >= startCol &&
        col < startCol + colSpan;
  }

  @override
  String toString() =>
      'MergedCell($content at [$startRow,$startCol] size ${rowSpan}x$colSpan)';
}
