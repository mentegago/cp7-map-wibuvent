import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BoothProximityData proximity;
  late Map<String, dynamic> rawData;

  setUpAll(() async {
    final raw = await File('data/booth-proximity.json').readAsString();
    rawData = json.decode(raw) as Map<String, dynamic>;
    proximity = BoothProximityData.fromJson(rawData);
  });

  test('generated metadata is present', () {
    expect(proximity.mapSha256, hasLength(64));
    expect(proximity.maxDistance, 32);
    expect(proximity.maxNeighbors, 48);
  });

  test('lookup table stays bounded for runtime memory and parsing cost', () {
    final booths = rawData['booths'] as List<dynamic>;
    final neighbors = rawData['neighbors'] as List<dynamic>;
    final neighborCounts =
        neighbors.map((entries) => (entries as List<dynamic>).length).toList();

    expect(neighbors, hasLength(booths.length));
    expect(neighborCounts.every((count) => count <= 48), isTrue);
    expect(neighborCounts.fold<int>(0, (sum, count) => sum + count),
        lessThanOrEqualTo(booths.length * 48));
  });

  test('same and nearby CP7 booths have short walking distances', () {
    expect(proximity.distanceBetween('A-1', 'A-1'), 0);
    expect(proximity.distanceBetween('A-1', 'A-2'), lessThanOrEqualTo(5));
  });

  test('CP7 proximity includes its mapped booths', () {
    final booths = (rawData['booths'] as List<dynamic>).cast<String>();
    expect(booths.length, greaterThan(500));
    expect(booths, containsAll(<String>['A-1', 'P-1', 'X-21']));
  });

  test('booth lookup normalizes CP7 booth numbers', () {
    expect(
      proximity.distanceBetween('A-001', 'A-2'),
      proximity.distanceBetween('A-1', 'A-002'),
    );
  });
}
