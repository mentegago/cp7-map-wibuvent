import 'dart:async';
import 'dart:convert';

import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Creator testCreator(int id) => Creator(
      id: id,
      name: 'Creator $id',
      spaces: [CreatorSpace(code: 'A-$id')],
      attendanceDates: const ['2026-10-31', '2026-11-01'],
      fandoms: [
        Fandom(
          id: 1,
          name: 'Blue Archive',
          kind: 'franchise',
          parentId: null,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('map and random opens remain exposure-only', () async {
    final service = RecommendationService();
    await service.initialize();

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.mapTap,
    );
    service.recordCreatorOpened(
      testCreator(2),
      CreatorSelectionSource.randomButton,
    );

    expect(service.profile.creatorInteractions, isEmpty);
  });

  test('direct creator deeplink contributes to the local profile', () async {
    final service = RecommendationService();
    await service.initialize();

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.deepLink,
    );

    final interaction = service.profile.creatorInteractions[1];
    expect(interaction, isNotNull);
    expect(interaction!.openStrength, 2.5);
    expect(interaction.consideration, 0.3);

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.deepLink,
    );
    expect(interaction.openStrength, 2.5);
  });

  test('meaningful engagement after map exposure is retained', () async {
    final service = RecommendationService();
    await service.initialize();
    final creator = testCreator(1);

    service.recordCreatorOpened(creator, CreatorSelectionSource.mapTap);
    service.recordSampleWorksViewed(creator);

    final interaction = service.profile.creatorInteractions[1];
    expect(interaction, isNotNull);
    expect(interaction!.sampleWorkViews, 1);
    expect(interaction.consideration, 0.5);
  });

  test('no profile data keeps the alphabetical-list fallback', () async {
    final service = RecommendationService(
      refreshDelay: const Duration(milliseconds: 20),
    );
    await service.initialize();
    final creators = [testCreator(1), testCreator(2), testCreator(3)];

    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );
  });

  test('home fandoms put interests first and fill from popular fandoms',
      () async {
    final service = RecommendationService();
    await service.initialize();
    final creators = [
      testCreator(1),
      Creator(
        id: 2,
        name: 'Creator 2',
        spaces: const [CreatorSpace(code: 'A-2')],
        attendanceDates: const ['2026-10-31', '2026-11-01'],
        fandoms: [
          Fandom(
            id: 2,
            name: 'Hololive',
            kind: 'publisher_umbrella',
            parentId: null,
          ),
        ],
      ),
    ];
    service.recordFandomInterest(1);
    final popular = [
      'Hololive',
      'Blue Archive',
      ...List.generate(25, (index) => 'Popular $index'),
    ];

    final suggestions = service.homeFandomSuggestionsFor(
      creators: creators,
      favoriteIds: const {},
      popularFandoms: popular,
    );

    expect(suggestions, hasLength(20));
    expect(suggestions.first, 'Blue Archive');
    expect(
        suggestions.where((fandom) => fandom == 'Blue Archive'), hasLength(1));
    expect(suggestions[1], 'Hololive');
    service.dispose();
  });

  test('fandom interest persists by canonical fandom ID', () async {
    final service = RecommendationService();
    await service.initialize();

    service.recordFandomInterest(34);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final raw = (await SharedPreferences.getInstance())
        .getString('cp7_recommendation_profile_v2');
    expect(raw, isNotNull);
    final profile = json.decode(raw!) as Map<String, dynamic>;
    final fandomSignals =
        profile['explicit_fandom_signals'] as Map<String, dynamic>;
    expect(fandomSignals.keys, contains('34'));
    service.dispose();
  });

  test('a visible home list stays steady while later results are queued',
      () async {
    final service = RecommendationService(
      refreshDelay: const Duration(milliseconds: 80),
    );
    await service.initialize();
    final creators = [
      testCreator(1),
      Creator(
        id: 2,
        name: 'Hololive Booth',
        spaces: const [CreatorSpace(code: 'B-2')],
        attendanceDates: const ['2026-10-31', '2026-11-01'],
        fandoms: [
          Fandom(
              id: 2,
              name: 'Hololive',
              kind: 'publisher_umbrella',
              parentId: null),
        ],
      ),
    ];
    service.setHomeVisible(true);
    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );

    var notifications = 0;
    final completer = Completer<void>();
    service.addListener(() {
      notifications++;
      if (!completer.isCompleted) completer.complete();
    });

    service.recordFandomInterest(1);
    await completer.future.timeout(const Duration(seconds: 5));
    final published = service.recommendationsFor(
      creators: creators,
      favoriteIds: const {},
    );
    expect(published, isNotEmpty);

    service.recordFandomInterest(2);
    service.recordFandomInterest(3);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(
      service.recommendationsFor(
          creators: creators,
          favoriteIds: const {}).map((result) => result.creator.id),
      published.map((result) => result.creator.id),
    );
    service.setHomeVisible(false);
    service.setHomeVisible(true);
    expect(notifications, 1);
    expect(
      service.recommendationsFor(creators: creators, favoriteIds: const {}),
      hasLength(2),
    );
    service.dispose();
  });

  test('a later calculation waits until after the previous completion',
      () async {
    final service = RecommendationService(
      refreshDelay: const Duration(milliseconds: 200),
    );
    await service.initialize();
    final creators = [testCreator(1), testCreator(2)];
    service.recommendationsFor(creators: creators, favoriteIds: const {});
    service.recordFandomInterest(1);
    final firstReady = Completer<void>();
    service.addListener(() {
      if (!firstReady.isCompleted) firstReady.complete();
    });
    await firstReady.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final preferences = await SharedPreferences.getInstance();
    final firstCache = preferences.getString('cp7_recommendation_results_v5');
    expect(firstCache, isNotNull);

    service.recordFandomInterest(2);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(preferences.getString('cp7_recommendation_results_v5'), firstCache);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(preferences.getString('cp7_recommendation_results_v5'),
        isNot(firstCache));
    service.dispose();
  });

  test('a valid saved recommendation is reused after reload', () async {
    final first = RecommendationService();
    await first.initialize();
    final creators = [testCreator(1), testCreator(2)];
    first.recommendationsFor(creators: creators, favoriteIds: const {});
    final ready = Completer<void>();
    first.addListener(() {
      if (!ready.isCompleted) ready.complete();
    });
    first.recordFandomInterest(1);
    await ready.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    first.dispose();

    final second = RecommendationService();
    await second.initialize();
    final restored = second.recommendationsFor(
      creators: creators,
      favoriteIds: const {},
    );
    expect(restored, isNotEmpty);
    second.dispose();
  });

  test('disabled service skips profiling and recommendation work', () async {
    final service = RecommendationService(disabled: true);
    await service.initialize();
    final creator = testCreator(1);

    service.recordCreatorOpened(creator, CreatorSelectionSource.deepLink);
    service.recordFandomInterest(1);
    service.recordSampleWorksViewed(creator);
    service.recordExternalLinkOpened(creator);
    service.recordCreatorShared(creator);
    service.recordFavoriteChanged(creator, true);

    expect(service.isInitialized, isTrue);
    expect(service.profile.creatorInteractions, isEmpty);
    expect(service.profile.explicitFandomSignals, isEmpty);
    expect(
      service.recommendationsFor(
        creators: [creator],
        favoriteIds: const {},
      ),
      isEmpty,
    );
  });
}
