import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_engine.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Creator booth(int id, String code, List<Fandom> fandoms,
        {List<String> days = const ['sat'], int images = 0}) =>
    Creator(
      id: id,
      name: 'Booth $id',
      spaces: [CreatorSpace(code: code)],
      attendanceDates: days,
      fandoms: fandoms,
      assets: CreatorAssets(gallery: List.filled(images, 'sample.jpg')),
    );

void main() {
  final gundam =
      Fandom(id: 1, name: 'Gundam', kind: 'franchise', parentId: null);
  final seed = Fandom(id: 2, name: 'SEED', kind: 'franchise', parentId: 1);
  final quux = Fandom(id: 3, name: 'GQuuuuuuX', kind: 'franchise', parentId: 1);
  final hoyo = Fandom(
      id: 4, name: 'HoYoverse', kind: 'publisher_umbrella', parentId: null);
  final genshin =
      Fandom(id: 5, name: 'Genshin', kind: 'franchise', parentId: 4);
  final starRail =
      Fandom(id: 6, name: 'Star Rail', kind: 'franchise', parentId: 4);
  final original =
      Fandom(id: 7, name: 'Original', kind: 'generic_tag', parentId: null);
  final registry = {
    for (final f in [gundam, seed, quux, hoyo, genshin, starRail, original])
      f.id: f
  };
  const engine = RecommendationEngine();
  final catalog = [
    booth(1, 'A-1', [seed]),
    booth(2, 'A-2', [seed]),
    booth(3, 'A-3', [quux]),
    booth(4, 'B-1', [genshin]),
    booth(5, 'B-2', [starRail]),
    booth(6, 'C-1', [original]),
  ];
  final gundamResults = engine.recommend(
    creators: catalog,
    allFandoms: registry,
    profile: RecommendationProfile(),
    favoriteIds: {1},
    sessionExposureIds: const {},
  );
  check(gundamResults.first.creator.id == 2, 'Exact match should lead');
  check(gundamResults.any((r) => r.creator.id == 3),
      'Gundam sibling should qualify');
  check(!gundamResults.any((r) => r.creator.id == 4 || r.creator.id == 6),
      'Unrelated and generic-only booths must not fill slots');

  final hoyoResults = engine.recommend(
    creators: catalog,
    allFandoms: registry,
    profile: RecommendationProfile(),
    favoriteIds: {4},
    sessionExposureIds: const {},
  );
  check(hoyoResults.any((r) => r.creator.id == 5),
      'Publisher sibling should qualify weakly');
  check(
      engine.recommend(
        creators: catalog,
        allFandoms: registry,
        profile: RecommendationProfile(),
        favoriteIds: {6},
        sessionExposureIds: const {},
      ).isEmpty,
      'Original alone is not a credible match');

  final explicitResults = engine.recommend(
    creators: catalog,
    allFandoms: registry,
    profile: RecommendationProfile(explicitFandomSignals: {
      seed.id: FandomSignal(strength: 5, lastUpdated: DateTime.now()),
    }),
    favoriteIds: const {},
    sessionExposureIds: const {},
  );
  check(explicitResults.isNotEmpty, 'Favorites are not required');

  final sampleCatalog = [
    booth(10, 'D-1', [seed]),
    booth(11, 'D-2', [seed], images: 1),
    booth(12, 'D-3', [seed], images: 8),
  ];
  final sampleResults = engine.recommend(
    creators: sampleCatalog,
    allFandoms: registry,
    profile: RecommendationProfile(explicitFandomSignals: {
      seed.id: FandomSignal(strength: 5, lastUpdated: DateTime.now()),
    }),
    favoriteIds: const {},
    sessionExposureIds: const {},
  );
  final one = sampleResults.singleWhere((r) => r.creator.id == 11);
  final many = sampleResults.singleWhere((r) => r.creator.id == 12);
  final none = sampleResults.singleWhere((r) => r.creator.id == 10);
  check(one.score == many.score && one.score > none.score,
      'Sample works must use a boolean boost');

  final popular = List.generate(50, (i) => booth(100 + i, 'E-$i', [seed]));
  final profile = RecommendationProfile(explicitFandomSignals: {
    seed.id: FandomSignal(strength: 5, lastUpdated: DateTime.now()),
  });
  final sets = [
    for (var seedValue = 1; seedValue <= 30; seedValue++)
      engine
          .recommend(
            creators: popular,
            allFandoms: registry,
            profile: profile,
            favoriteIds: const {},
            sessionExposureIds: const {},
            userSeed: seedValue,
          )
          .map((r) => r.creator.id)
          .toSet(),
  ];
  final overlap = <int>[];
  for (var i = 0; i < sets.length; i++) {
    for (var j = i + 1; j < sets.length; j++) {
      overlap.add(sets[i].intersection(sets[j]).length);
    }
  }
  overlap.sort();
  check(overlap[overlap.length ~/ 2] <= 5,
      'Similar users should see substantially varied strong matches');

  final proximity = BoothProximityData.fromJson({
    'schema_version': 1,
    'booths': ['F-1', 'F-2'],
    'neighbors': [
      [
        [1, 1]
      ],
      [
        [0, 1]
      ]
    ],
  });
  final nearEngine = RecommendationEngine(boothProximity: proximity);
  final anchors = List.generate(21, (i) => booth(200 + i, 'G-$i', [seed]));
  anchors[20] = booth(220, 'F-1', [seed]);
  final near = booth(300, 'F-2', [seed]);
  final nearResults = nearEngine.recommend(
    creators: [...anchors, near],
    allFandoms: registry,
    profile: RecommendationProfile(),
    favoriteIds: anchors.map((c) => c.id).toSet(),
    sessionExposureIds: const {},
  );
  check(nearResults.single.itineraryAffinity > 0,
      'Favorites after the twentieth must count as anchors');

  final yuri = Fandom(
      id: 225, name: 'Girls Love / Yuri', kind: 'generic_tag', parentId: null);
  final blue =
      Fandom(id: 1, name: 'Blue Archive', kind: 'franchise', parentId: null);
  final unevenCatalog = [
    booth(1000, 'H-1', [yuri, blue]),
    booth(1001, 'H-2', [yuri, blue]),
    for (var i = 0; i < 11; i++) booth(1010 + i, 'J-$i', [yuri]),
    for (var i = 0; i < 550; i++) booth(2000 + i, 'K-$i', [blue]),
  ];
  final yuriProfile = RecommendationProfile(explicitFandomSignals: {
    yuri.id: FandomSignal(strength: 5, lastUpdated: DateTime.now()),
  });
  final unevenResults = engine.recommend(
    creators: unevenCatalog,
    allFandoms: {yuri.id: yuri, blue.id: blue},
    profile: yuriProfile,
    favoriteIds: {1000, 1001},
    sessionExposureIds: const {},
    userSeed: 42,
  );
  final yuriCount = unevenResults
      .where((r) => r.creator.fandoms.any((f) => f.id == yuri.id))
      .length;
  check(yuriCount >= 7,
      'Explicit Yuri interest must not be swamped by a larger fandom pool');
  final favoriteOnlyResults = engine.recommend(
    creators: unevenCatalog,
    allFandoms: {yuri.id: yuri, blue.id: blue},
    profile: RecommendationProfile(),
    favoriteIds: {1000},
    sessionExposureIds: const {},
  );
  check(
      favoriteOnlyResults
          .any((r) => r.creator.fandoms.any((f) => f.id == yuri.id)),
      'A specific generic tag on a favorite should qualify exact matches');
  print('Recommendation algorithm checks passed');
}
