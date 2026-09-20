import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/services/map_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses semantic CF23 map features and sectionless booths', () {
    final layout = MapParser.parseMapLayout({
      'schemaVersion': 2,
      'bounds': {'width': 4610, 'height': 1818},
      'features': [
        {
          'uid': 'booth-1',
          'id': 'Y-32b',
          'kind': 'booth',
          'status': 'accepted',
          'geometry': {
            'type': 'rect',
            'x': 10.5,
            'y': 20.25,
            'width': 14.4,
            'height': 30.7,
          },
        },
        {
          'uid': 'booth-2',
          'id': '1207',
          'kind': 'booth',
          'status': 'accepted',
          'geometry': {
            'type': 'rect',
            'x': 30,
            'y': 40,
            'width': 50,
            'height': 60,
          },
        },
        {
          'uid': 'stage',
          'kind': 'highlight',
          'type': 'section-marker',
          'label': 'STAGE',
          'color': '#a99ac0',
          'rotation': 90,
          'status': 'accepted',
          'geometry': {
            'type': 'rect',
            'x': 100,
            'y': 120,
            'width': 80,
            'height': 140,
          },
        },
      ],
    });

    expect(layout.schemaVersion, 2);
    expect(layout.width, 4610);
    expect(layout.features, hasLength(3));
    expect(layout.features[0].content, 'Y-32b');
    expect(layout.features[0].type, isNull);
    expect(layout.features[0].displayLabel, '32');
    expect(layout.features[1].isBooth, isTrue);
    expect(layout.features[1].content, '1207');
    expect(layout.features[1].displayLabel, '1207');
    expect(layout.features[2].isHighlight, isTrue);
    expect(layout.features[2].isSectionMarker, isTrue);
    expect(layout.features[2].rotation, 90);
  });

  test('keeps the legacy grid format compatible', () {
    final layout = MapParser.parseMapLayout([
      ['A-01', 'A-01', ''],
      ['STAFF', '', ''],
    ]);

    expect(layout.schemaVersion, 1);
    expect(layout.features.where((feature) => feature.isBooth), hasLength(1));
    expect(layout.features.first.width, MapParser.legacyCellSize * 2);
  });

  test('parses walls, arrows, and theme-aware text indicators', () {
    final layout = MapParser.parseMapLayout({
      'schemaVersion': 2,
      'bounds': {'width': 500, 'height': 300},
      'features': [
        {
          'uid': 'wall',
          'kind': 'wall',
          'label': '',
          'themeAware': true,
          'thickness': 8,
          'geometry': {
            'type': 'rect',
            'x': 10,
            'y': 20,
            'width': 200,
            'height': 0.1,
          },
          'lineStart': {'x': 0, 'y': 0.5},
          'lineEnd': {'x': 1, 'y': 0.5},
        },
        {
          'uid': 'arrow',
          'kind': 'arrow',
          'label': '',
          'color': '#2563eb',
          'thickness': 3,
          'geometry': {
            'type': 'rect',
            'x': 20,
            'y': 40,
            'width': 100,
            'height': 80,
          },
          'lineStart': {'x': 1, 'y': 0},
          'lineEnd': {'x': 0, 'y': 1},
        },
        {
          'uid': 'label',
          'kind': 'text',
          'label': 'Entrance',
          'fontSize': 20,
          'geometry': {
            'type': 'rect',
            'x': 100,
            'y': 100,
            'width': 120,
            'height': 40,
          },
        },
      ],
    });

    expect(layout.features[0].isLineIndicator, isTrue);
    expect(layout.features[0].thickness, 8);
    expect(layout.features[1].isArrow, isTrue);
    expect(layout.features[1].lineStartX, 1);
    expect(layout.features[1].lineEndY, 1);
    expect(layout.features[2].isText, isTrue);
    expect(layout.features[2].themeAware, isTrue);
    expect(layout.features[2].fontSize, 20);
  });

  test('the bundled Comipara 7 map asset parses completely', () {
    final source = json.decode(File('data/map.json').readAsStringSync());
    final layout = MapParser.parseMapLayout(source);

    expect(layout.schemaVersion, 2);
    expect(layout.features.length, greaterThan(3000));
    expect(
      layout.features.where(
        (feature) =>
            feature.isBooth && RegExp(r'^\d').hasMatch(feature.content),
      ),
      isNotEmpty,
    );
    expect(layout.features.where((feature) => feature.isHighlight), isNotEmpty);
    expect(
      layout.features.where((feature) => feature.isSectionMarker).length,
      109,
    );
    expect(
      layout.features.where((feature) => feature.isBoothSuffixMarker).length,
      2854,
    );
  });
}
