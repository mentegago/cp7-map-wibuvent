import 'dart:convert';

import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog initializes and is cached for offline launches',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = CreatorDataProvider(enableRemoteUpdates: false);

    await provider.initialize();

    expect(provider.creators, hasLength(363));
    expect(provider.fandomById, isNotEmpty);
    final cachedSnapshot = (await SharedPreferences.getInstance())
        .getString('cp7_catalog_snapshot_v3');
    expect(cachedSnapshot, isNotNull);
    final cachedJson = json.decode(cachedSnapshot!) as Map<String, dynamic>;
    expect(cachedJson['version'], isPositive);
    expect(cachedJson['catalog'], isA<Map>());
    expect(cachedJson['fandomRegistry'], isA<Map>());

    provider.dispose();

    final cachedProvider = CreatorDataProvider(enableRemoteUpdates: false);
    await cachedProvider.initialize();
    expect(cachedProvider.creators, hasLength(363));
    expect(cachedProvider.fandomIdForName('Blue Archive'), isNotNull);
    cachedProvider.dispose();
  });
}
