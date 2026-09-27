import 'creator.dart';

enum CreatorSelectionSource {
  searchResult,
  allCreators,
  recommendation,
  favorites,
  customList,
  mapTap,
  randomButton,
  deepLink,
}

CreatorSelectionSource creatorSelectionSourceFromString(
  String source, {
  String searchQuery = '',
}) {
  return switch (source) {
    'map' => CreatorSelectionSource.mapTap,
    'random' => CreatorSelectionSource.randomButton,
    'recommendation' => CreatorSelectionSource.recommendation,
    'favorites' => CreatorSelectionSource.favorites,
    'custom_list' => CreatorSelectionSource.customList,
    'deeplink' || 'deeplink_search_bar' => CreatorSelectionSource.deepLink,
    _ when searchQuery.trim().isNotEmpty => CreatorSelectionSource.searchResult,
    _ => CreatorSelectionSource.allCreators,
  };
}

class FandomSignal {
  double strength;
  DateTime lastUpdated;

  FandomSignal({required this.strength, required this.lastUpdated});

  factory FandomSignal.fromJson(Map<String, dynamic> json) {
    return FandomSignal(
      strength: (json['strength'] as num?)?.toDouble() ?? 0,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        (json['last_updated'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'strength': strength,
        'last_updated': lastUpdated.millisecondsSinceEpoch,
      };
}

class CreatorInteraction {
  double openStrength;
  int deliberateOpenCount;
  int sampleWorkViews;
  int externalLinkClicks;
  int shares;
  bool favorite;
  double consideration;
  DateTime lastUpdated;

  CreatorInteraction({
    this.openStrength = 0,
    this.deliberateOpenCount = 0,
    this.sampleWorkViews = 0,
    this.externalLinkClicks = 0,
    this.shares = 0,
    this.favorite = false,
    this.consideration = 0,
    required this.lastUpdated,
  });

  factory CreatorInteraction.fromJson(Map<String, dynamic> json) {
    return CreatorInteraction(
      openStrength: (json['open_strength'] as num?)?.toDouble() ?? 0,
      deliberateOpenCount:
          (json['deliberate_open_count'] as num?)?.toInt() ?? 0,
      sampleWorkViews: (json['sample_work_views'] as num?)?.toInt() ?? 0,
      externalLinkClicks: (json['external_link_clicks'] as num?)?.toInt() ?? 0,
      shares: (json['shares'] as num?)?.toInt() ?? 0,
      favorite: json['favorite'] as bool? ?? false,
      consideration: (json['consideration'] as num?)?.toDouble() ?? 0,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        (json['last_updated'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'open_strength': openStrength,
        'deliberate_open_count': deliberateOpenCount,
        'sample_work_views': sampleWorkViews,
        'external_link_clicks': externalLinkClicks,
        'shares': shares,
        'favorite': favorite,
        'consideration': consideration,
        'last_updated': lastUpdated.millisecondsSinceEpoch,
      };
}

class RecommendationProfile {
  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final Map<int, FandomSignal> explicitFandomSignals;
  final Map<int, CreatorInteraction> creatorInteractions;

  RecommendationProfile({
    this.schemaVersion = currentSchemaVersion,
    Map<int, FandomSignal>? explicitFandomSignals,
    Map<int, CreatorInteraction>? creatorInteractions,
  })  : explicitFandomSignals = explicitFandomSignals ?? {},
        creatorInteractions = creatorInteractions ?? {};

  factory RecommendationProfile.fromJson(Map<String, dynamic> json) {
    final rawFandoms = json['explicit_fandom_signals'];
    final rawCreators = json['creator_interactions'];

    return RecommendationProfile(
      schemaVersion:
          (json['schema_version'] as num?)?.toInt() ?? currentSchemaVersion,
      explicitFandomSignals: rawFandoms is Map
          ? rawFandoms.map(
              (key, value) => MapEntry(
                int.parse(key.toString()),
                FandomSignal.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              ),
            )
          : {},
      creatorInteractions: rawCreators is Map
          ? rawCreators.map(
              (key, value) => MapEntry(
                int.parse(key.toString()),
                CreatorInteraction.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ),
              ),
            )
          : {},
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'explicit_fandom_signals': explicitFandomSignals.map(
          (key, value) => MapEntry(key.toString(), value.toJson()),
        ),
        'creator_interactions': creatorInteractions.map(
          (key, value) => MapEntry(key.toString(), value.toJson()),
        ),
      };
}

class RecommendationResult {
  final Creator creator;
  final double score;
  final double fandomAffinity;
  final double itineraryAffinity;
  final List<String> matchingFandoms;
  final List<int> nearbyPlannedCreatorIds;
  final int matchTier;

  const RecommendationResult({
    required this.creator,
    required this.score,
    required this.fandomAffinity,
    required this.itineraryAffinity,
    this.matchingFandoms = const [],
    this.nearbyPlannedCreatorIds = const [],
    this.matchTier = 0,
  });
}
