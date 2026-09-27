import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const fandomIds = {
  'Blue Archive': 1,
  'Hololive': 2,
  'Touhou': 3,
  'HoYoverse': 9,
  'Genshin Impact': 4,
};

Creator creator(int id, String booth, List<String> fandomNames) => Creator(
      id: id,
      name: 'Creator $id',
      spaces: [CreatorSpace(code: booth)],
      attendanceDates: const ['2026-10-31', '2026-11-01'],
      fandoms: fandomNames
          .map((name) => Fandom(
                id: fandomIds[name]!,
                name: name,
                kind: 'franchise',
                parentId: name == 'Genshin Impact' ? 9 : null,
              ))
          .toList(),
    );

void main() {
  final now = DateTime(2026, 8, 22);

  test('no profile data produces no personalized recommendations', () {
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Hololive']),
      ],
      profile: RecommendationProfile(),
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results, isEmpty);
  });

  test('explicit fandom interest promotes matching creators', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        1: FandomSignal(strength: 5, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Hololive']),
      ],
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.first.creator.id, 1);
    expect(results.first.matchingFandoms, contains('Blue Archive'));
  });

  test('parent fandom interest promotes creators in child franchises', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        9: FandomSignal(strength: 5, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Genshin Impact']),
        creator(2, 'B-1', ['Hololive']),
      ],
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.first.creator.id, 1);
    expect(results.first.matchingFandoms, contains('Genshin Impact'));
  });

  test('matching fandoms are ordered by their contribution', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        1: FandomSignal(strength: 5, lastUpdated: now),
        2: FandomSignal(strength: 2, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Hololive', 'Blue Archive']),
      ],
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.single.matchingFandoms, ['Blue Archive', 'Hololive']);
  });

  test('interested fandoms are ranked using the recommendation profile', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        1: FandomSignal(strength: 5, lastUpdated: now),
        2: FandomSignal(strength: 2, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();

    expect(
      engine.rankedInterestedFandoms(
        creators: [
          creator(1, 'A-1', ['Hololive']),
          creator(2, 'A-2', ['Blue Archive']),
          creator(3, 'A-3', ['Touhou']),
        ],
        profile: profile,
        favoriteIds: const {},
        now: now,
      ),
      ['Blue Archive', 'Hololive'],
    );
  });

  test('existing favorites seed fandom interest without prior profile data',
      () {
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Blue Archive']),
        creator(3, 'C-1', ['Hololive']),
      ],
      profile: RecommendationProfile(),
      favoriteIds: {1},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.first.creator.id, 2);
  });

  test('specific generic tags from favorites qualify exact matches', () {
    const engine = RecommendationEngine();
    final yuri = Fandom(
      id: 225,
      name: 'Girls Love / Yuri',
      kind: 'generic_tag',
      parentId: null,
    );
    final blue = Fandom(
      id: 1,
      name: 'Blue Archive',
      kind: 'franchise',
      parentId: null,
    );
    Creator tagged(int id, Fandom fandom) => Creator(
          id: id,
          name: 'Creator $id',
          spaces: [CreatorSpace(code: 'A-$id')],
          attendanceDates: const ['2026-10-31'],
          fandoms: [fandom],
        );
    final creators = [
      for (var id = 1; id <= 8; id++) tagged(id, yuri),
      for (var id = 9; id <= 100; id++) tagged(id, blue),
    ];

    final results = engine.recommend(
      creators: creators,
      profile: RecommendationProfile(),
      favoriteIds: {1},
      sessionExposureIds: const {},
      now: now,
    );

    expect(results.map((result) => result.creator.id).toSet(),
        {for (var id = 2; id <= 8; id++) id});
  });

  test('explicit Yuri interest is not crowded out by Blue Archive volume', () {
    const engine = RecommendationEngine();
    final yuri = Fandom(
      id: 225,
      name: 'Girls Love / Yuri',
      kind: 'generic_tag',
      parentId: null,
    );
    final blue = Fandom(
      id: 1,
      name: 'Blue Archive',
      kind: 'franchise',
      parentId: null,
    );
    Creator tagged(int id, List<Fandom> fandoms) => Creator(
          id: id,
          name: 'Creator $id',
          spaces: [CreatorSpace(code: 'A-$id')],
          attendanceDates: const ['2026-10-31'],
          fandoms: fandoms,
        );
    final creators = [
      tagged(1, [yuri, blue]),
      tagged(2, [yuri, blue]),
      for (var id = 3; id <= 13; id++) tagged(id, [yuri]),
      for (var id = 14; id <= 563; id++) tagged(id, [blue]),
    ];
    final profile = RecommendationProfile(explicitFandomSignals: {
      yuri.id: FandomSignal(strength: 5, lastUpdated: now),
    });

    final results = engine.recommend(
      creators: creators,
      profile: profile,
      favoriteIds: {1, 2},
      sessionExposureIds: const {},
      userSeed: 42,
      now: now,
    );

    expect(
      results.where((result) => result.creator.fandoms.contains(yuri)).length,
      greaterThanOrEqualTo(7),
    );
  });

  test('booth proximity uses precomputed walking distance', () {
    final profile = RecommendationProfile(
      creatorInteractions: {
        1: CreatorInteraction(
          favorite: true,
          consideration: 1,
          lastUpdated: now,
        ),
      },
    );
    final proximity = BoothProximityData.fromJson({
      'schema_version': 1,
      'map_sha256': 'test',
      'max_distance': 32,
      'max_neighbors': 48,
      'booths': ['AA-10', 'AA-12', 'AB-10'],
      'neighbors': [
        [
          [1, 4],
        ],
        [
          [0, 4],
        ],
        [],
      ],
    });
    final engine = RecommendationEngine(boothProximity: proximity);
    final results = engine.recommend(
      creators: [
        creator(1, 'AA-10', ['Blue Archive']),
        creator(2, 'AA-10', ['Blue Archive']),
        creator(3, 'AA-12', ['Blue Archive']),
        creator(4, 'AB-10', ['Blue Archive']),
      ],
      profile: profile,
      favoriteIds: {1},
      sessionExposureIds: {},
      now: now,
    );

    final sameNumber = results.singleWhere((result) => result.creator.id == 2);
    final closeNumber = results.singleWhere((result) => result.creator.id == 3);
    final differentSection =
        results.singleWhere((result) => result.creator.id == 4);
    expect(sameNumber.itineraryAffinity, 1);
    expect(
      sameNumber.itineraryAffinity,
      greaterThan(closeNumber.itineraryAffinity),
    );
    expect(closeNumber.itineraryAffinity, greaterThan(0));
    expect(differentSection.itineraryAffinity, 0);
    expect(sameNumber.nearbyPlannedCreatorIds, contains(1));
  });

  test('asynchronous ranking matches synchronous ranking', () async {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        1: FandomSignal(strength: 5, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final creators = [
      creator(1, 'A-1', ['Blue Archive']),
      creator(2, 'B-1', ['Hololive']),
      creator(3, 'C-1', ['Blue Archive']),
    ];

    final synchronous = engine.recommend(
      creators: creators,
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );
    final asynchronous = await engine.recommendAsync(
      creators: creators,
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(
      asynchronous.map((result) => result.creator.id),
      synchronous.map((result) => result.creator.id),
    );
  });
}
