class BoothProximityData {
  static const int currentSchemaVersion = 1;
  static const BoothProximityData empty = BoothProximityData._(
    boothIndices: {},
    booths: [],
    distances: [],
    mapSha256: '',
    maxDistance: 0,
    maxNeighbors: 0,
  );

  final Map<String, int> _boothIndices;
  final List<String> _booths;
  final List<Map<int, int>> _distances;
  final String mapSha256;
  final int maxDistance;
  final int maxNeighbors;

  const BoothProximityData._({
    required Map<String, int> boothIndices,
    required List<String> booths,
    required List<Map<int, int>> distances,
    required this.mapSha256,
    required this.maxDistance,
    required this.maxNeighbors,
  })  : _boothIndices = boothIndices,
        _booths = booths,
        _distances = distances;

  factory BoothProximityData.fromJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schema_version'] as num?)?.toInt();
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported booth proximity schema: $schemaVersion',
      );
    }

    final booths = (json['booths'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];
    final rawNeighbors = json['neighbors'] as List<dynamic>?;
    if (rawNeighbors == null || rawNeighbors.length != booths.length) {
      throw const FormatException('Invalid booth proximity neighbor table');
    }

    final distances = <Map<int, int>>[];
    for (final rawList in rawNeighbors) {
      final entries = <int, int>{};
      for (final rawPair in rawList as List<dynamic>) {
        final pair = rawPair as List<dynamic>;
        if (pair.length != 2) {
          throw const FormatException('Invalid booth proximity entry');
        }
        final target = (pair[0] as num).toInt();
        final distance = (pair[1] as num).toInt();
        if (target < 0 || target >= booths.length || distance < 0) {
          throw const FormatException('Out-of-range booth proximity entry');
        }
        entries[target] = distance;
      }
      distances.add(entries);
    }

    return BoothProximityData._(
      boothIndices: {
        for (var index = 0; index < booths.length; index++)
          booths[index]: index,
      },
      booths: booths,
      distances: distances,
      mapSha256: json['map_sha256']?.toString() ?? '',
      maxDistance: (json['max_distance'] as num?)?.toInt() ?? 0,
      maxNeighbors: (json['max_neighbors'] as num?)?.toInt() ?? 0,
    );
  }

  int? distanceBetween(String firstBooth, String secondBooth) {
    final first =
        _boothIndices[firstBooth] ?? _boothIndices[canonicalBooth(firstBooth)];
    final second = _boothIndices[secondBooth] ??
        _boothIndices[canonicalBooth(secondBooth)];
    if (first == null || second == null) return null;
    if (first == second) return 0;
    return _distances[first][second] ?? _distances[second][first];
  }

  Map<String, int> neighborsOf(String booth) {
    final index = _boothIndices[booth] ?? _boothIndices[canonicalBooth(booth)];
    if (index == null) return const {};
    return {
      for (final entry in _distances[index].entries)
        _booths[entry.key]: entry.value,
    };
  }

  static String canonicalBooth(String booth) {
    final match = RegExp(r'^(?:([A-Z]+)-)?0*(\d+)([A-Z]?)$')
        .firstMatch(booth.trim().toUpperCase());
    if (match == null) return booth.trim();
    final number = int.tryParse(match.group(2)!);
    if (number == null) return booth.trim();
    final normalized = '$number${match.group(3)!.toLowerCase()}';
    final section = match.group(1);
    return section == null ? normalized : '$section-$normalized';
  }
}
