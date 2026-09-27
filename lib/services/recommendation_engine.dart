import 'dart:math';

import '../models/booth_proximity.dart';
import '../models/creator.dart';
import '../models/fandom.dart';
import '../models/recommendation.dart';

class RecommendationEngine {
  static const double _itineraryWeight = 0.08;
  static const double _sampleWorkBoost = 0.035;
  static const double _walkingDistanceScale = 8;
  static final Expando<_FandomCatalog> _fandomCatalogs =
      Expando<_FandomCatalog>();

  final BoothProximityData boothProximity;

  const RecommendationEngine({
    this.boothProximity = BoothProximityData.empty,
  });

  List<String> rankedInterestedFandoms({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    Map<int, Fandom> allFandoms = const {},
    DateTime? now,
  }) {
    if (creators.isEmpty) return const [];

    final catalog = _fandomCatalog(creators, allFandoms);
    final interestVector = _buildInterestVector(
      creatorsById: {for (final creator in creators) creator.id: creator},
      profile: profile,
      favoriteIds: favoriteIds,
      catalog: catalog,
      now: now ?? DateTime.now(),
    );
    final ranked = interestVector.entries
        .where((entry) => catalog.displayById.containsKey(entry.key))
        .toList()
      ..sort((a, b) {
        final strength = b.value.compareTo(a.value);
        if (strength != 0) return strength;
        final popularity = (catalog.documentFrequency[b.key] ?? 0)
            .compareTo(catalog.documentFrequency[a.key] ?? 0);
        if (popularity != 0) return popularity;
        return a.key.compareTo(b.key);
      });
    return ranked.map((entry) => catalog.displayById[entry.key]!).toList();
  }

  Future<List<RecommendationResult>> recommendAsync({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    Map<int, Fandom> allFandoms = const {},
    int userSeed = 0,
    Set<int> previousIds = const {},
    DateTime? now,
    int limit = 10,
    bool Function()? isCancelled,
  }) async {
    if (creators.isEmpty || limit <= 0) return [];

    final budget = _AsyncBudget();
    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomCatalog = await _fandomCatalogAsync(
      creators,
      allFandoms: allFandoms,
      budget: budget,
      isCancelled: isCancelled,
    );
    if (fandomCatalog == null) return [];

    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      catalog: fandomCatalog,
      now: currentTime,
    );
    _removeUnqualifiedGenericInterests(
      interestVector,
      profile: profile,
      creatorsById: creatorsById,
      catalog: fandomCatalog,
    );
    await budget.checkpoint(force: true);
    if (isCancelled?.call() ?? false) return [];

    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );
    if (interestVector.isEmpty) return [];
    final eligible = _eligibleCreators(interestVector.keys, fandomCatalog);
    final nearbyAffinities = _nearbyAffinities(anchors, fandomCatalog);
    if (isCancelled?.call() ?? false) return [];

    final candidates = <RecommendationResult>[];
    for (var index = 0; index < eligible.length; index++) {
      if (isCancelled?.call() ?? false) return [];
      final creator = eligible[index];
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomCatalog,
        creators.length,
      );
      if (fandom.affinity <= 0) continue;
      final itinerary = nearbyAffinities[creator.id] ??
          (affinity: 0.0, nearbyCreatorIds: <int>[]);
      final score = fandom.affinity +
          _itineraryWeight * itinerary.affinity +
          (creator.assets.gallery.isNotEmpty ? _sampleWorkBoost : 0);

      candidates.add(
        RecommendationResult(
          creator: creator,
          score: score,
          fandomAffinity: fandom.affinity,
          itineraryAffinity: itinerary.affinity,
          matchingFandoms: fandom.matchingFandoms,
          nearbyPlannedCreatorIds: itinerary.nearbyCreatorIds,
          matchTier: fandom.tier,
        ),
      );
      if (index % 16 == 0) await budget.checkpoint();
    }

    return _selectDiverseAsync(
      candidates,
      limit,
      budget: budget,
      userSeed: userSeed,
      previousIds: previousIds,
      isCancelled: isCancelled,
    );
  }

  List<RecommendationResult> recommend({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    Map<int, Fandom> allFandoms = const {},
    int userSeed = 0,
    Set<int> previousIds = const {},
    DateTime? now,
    int limit = 10,
  }) {
    if (creators.isEmpty || limit <= 0) return [];

    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomCatalog = _fandomCatalog(creators, allFandoms);
    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      catalog: fandomCatalog,
      now: currentTime,
    );
    _removeUnqualifiedGenericInterests(
      interestVector,
      profile: profile,
      creatorsById: creatorsById,
      catalog: fandomCatalog,
    );
    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );
    if (interestVector.isEmpty) return [];
    final eligible = _eligibleCreators(interestVector.keys, fandomCatalog);
    final nearbyAffinities = _nearbyAffinities(anchors, fandomCatalog);

    final candidates = <RecommendationResult>[];
    for (final creator in eligible) {
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomCatalog,
        creators.length,
      );
      if (fandom.affinity <= 0) continue;
      final itinerary = nearbyAffinities[creator.id] ??
          (affinity: 0.0, nearbyCreatorIds: <int>[]);
      final score = fandom.affinity +
          _itineraryWeight * itinerary.affinity +
          (creator.assets.gallery.isNotEmpty ? _sampleWorkBoost : 0);

      candidates.add(
        RecommendationResult(
          creator: creator,
          score: score,
          fandomAffinity: fandom.affinity,
          itineraryAffinity: itinerary.affinity,
          matchingFandoms: fandom.matchingFandoms,
          nearbyPlannedCreatorIds: itinerary.nearbyCreatorIds,
          matchTier: fandom.tier,
        ),
      );
    }

    return _selectDiverse(
      candidates,
      limit,
      userSeed: userSeed,
      previousIds: previousIds,
    );
  }

  List<Creator> _eligibleCreators(
    Iterable<int> interestIds,
    _FandomCatalog catalog,
  ) {
    final result = <int, Creator>{};
    for (final interestId in interestIds) {
      for (final ancestor in _ancestors(interestId, catalog).keys) {
        final kind = catalog.fandomById[ancestor]?.kind;
        if (kind == 'generic_tag' && ancestor != interestId) continue;
        for (final creator
            in catalog.creatorsByAncestor[ancestor] ?? const <Creator>[]) {
          result[creator.id] = creator;
        }
      }
    }
    return result.values.toList();
  }

  Map<int, double> _buildInterestVector({
    required Map<int, Creator> creatorsById,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required _FandomCatalog catalog,
    required DateTime now,
  }) {
    final vector = <int, double>{};

    for (final entry in profile.explicitFandomSignals.entries) {
      final value = _decay(
        entry.value.strength,
        entry.value.lastUpdated,
        const Duration(days: 60),
        now,
      );
      if (value > 0.01) vector[entry.key] = value;
    }

    for (final entry in profile.creatorInteractions.entries) {
      final creator = creatorsById[entry.key];
      if (creator == null || creator.fandoms.isEmpty) continue;

      final interaction = entry.value;
      final behaviorStrength = min(interaction.openStrength, 6) +
          min(interaction.sampleWorkViews, 3) * 4 +
          min(interaction.externalLinkClicks, 2) * 5 +
          min(interaction.shares, 2) * 4;
      if (behaviorStrength <= 0.5 && !favoriteIds.contains(entry.key)) {
        continue;
      }
      final decayedBehavior = _decay(
        min(behaviorStrength, 5).toDouble(),
        interaction.lastUpdated,
        const Duration(days: 30),
        now,
      );
      final totalStrength =
          decayedBehavior + (favoriteIds.contains(entry.key) ? 10 : 0);
      if (totalStrength <= 0.01) continue;

      final divisor = sqrt(creator.fandoms.length);
      for (final fandom in creator.fandoms) {
        vector[fandom.id] = (vector[fandom.id] ?? 0) + totalStrength / divisor;
      }
    }

    for (final favoriteId in favoriteIds) {
      if (profile.creatorInteractions.containsKey(favoriteId)) continue;
      final creator = creatorsById[favoriteId];
      if (creator == null || creator.fandoms.isEmpty) continue;
      final divisor = sqrt(creator.fandoms.length);
      for (final fandom in creator.fandoms) {
        vector[fandom.id] = (vector[fandom.id] ?? 0) + 10 / divisor;
      }
    }

    final maximum = vector.values.fold<double>(0, max);
    if (maximum > 0) {
      vector.updateAll((_, value) => value / maximum);
    }
    return vector;
  }

  void _removeUnqualifiedGenericInterests(
    Map<int, double> vector, {
    required RecommendationProfile profile,
    required Map<int, Creator> creatorsById,
    required _FandomCatalog catalog,
  }) {
    vector.removeWhere((fandomId, _) {
      if (catalog.fandomById[fandomId]?.kind != 'generic_tag') return false;
      if (profile.explicitFandomSignals.containsKey(fandomId)) return false;
      final frequency = catalog.documentFrequency[fandomId] ?? 0;
      return frequency > creatorsById.length * 0.1;
    });
    final maximum = vector.values.fold<double>(0, max);
    if (maximum > 0) {
      vector.updateAll((_, value) => value / maximum);
    }
  }

  _FandomCatalog _fandomCatalog(
      List<Creator> creators, Map<int, Fandom> allFandoms) {
    final cached = _fandomCatalogs[creators];
    if (cached != null && identical(cached.sourceRegistry, allFandoms)) {
      return cached;
    }

    final frequency = <int, int>{};
    final entriesByCreatorId = <int, List<Fandom>>{};
    final displayById = <int, String>{};
    final fandomById = <int, Fandom>{...allFandoms};
    final creatorsByBooth = <String, List<Creator>>{};
    for (final creator in creators) {
      final entries = creator.fandoms;
      final uniqueFandoms = <int>{
        for (final entry in entries) ...[
          entry.id,
          if (entry.parentId != null) entry.parentId!,
        ],
      };
      for (final fandom in uniqueFandoms) {
        frequency[fandom] = (frequency[fandom] ?? 0) + 1;
      }
      for (final entry in entries) {
        displayById.putIfAbsent(entry.id, () => entry.name);
        fandomById[entry.id] = entry;
      }
      entriesByCreatorId[creator.id] = entries;
      for (final booth in creator.booths) {
        creatorsByBooth
            .putIfAbsent(BoothProximityData.canonicalBooth(booth), () => [])
            .add(creator);
      }
    }
    final catalog = _FandomCatalog(
      documentFrequency: frequency,
      entriesByCreatorId: entriesByCreatorId,
      displayById: displayById,
      fandomById: fandomById,
      creatorsByBooth: creatorsByBooth,
      creatorsByAncestor: _indexAncestors(creators, fandomById),
      sourceRegistry: allFandoms,
    );
    _fandomCatalogs[creators] = catalog;
    return catalog;
  }

  Future<_FandomCatalog?> _fandomCatalogAsync(
    List<Creator> creators, {
    required Map<int, Fandom> allFandoms,
    required _AsyncBudget budget,
    bool Function()? isCancelled,
  }) async {
    final cached = _fandomCatalogs[creators];
    if (cached != null && identical(cached.sourceRegistry, allFandoms)) {
      return cached;
    }

    final frequency = <int, int>{};
    final entriesByCreatorId = <int, List<Fandom>>{};
    final displayById = <int, String>{};
    final fandomById = <int, Fandom>{...allFandoms};
    final creatorsByBooth = <String, List<Creator>>{};
    for (var index = 0; index < creators.length; index++) {
      if (isCancelled?.call() ?? false) return null;
      final creator = creators[index];
      final entries = creator.fandoms;
      final uniqueFandoms = <int>{
        for (final entry in entries) ...[
          entry.id,
          if (entry.parentId != null) entry.parentId!,
        ],
      };
      for (final fandom in uniqueFandoms) {
        frequency[fandom] = (frequency[fandom] ?? 0) + 1;
      }
      for (final entry in entries) {
        displayById.putIfAbsent(entry.id, () => entry.name);
        fandomById[entry.id] = entry;
      }
      entriesByCreatorId[creator.id] = entries;
      for (final booth in creator.booths) {
        creatorsByBooth
            .putIfAbsent(BoothProximityData.canonicalBooth(booth), () => [])
            .add(creator);
      }
      if (index % 32 == 0) await budget.checkpoint();
    }
    final catalog = _FandomCatalog(
      documentFrequency: frequency,
      entriesByCreatorId: entriesByCreatorId,
      displayById: displayById,
      fandomById: fandomById,
      creatorsByBooth: creatorsByBooth,
      creatorsByAncestor: _indexAncestors(creators, fandomById),
      sourceRegistry: allFandoms,
    );
    _fandomCatalogs[creators] = catalog;
    return catalog;
  }

  Map<int, List<Creator>> _indexAncestors(
    List<Creator> creators,
    Map<int, Fandom> fandomById,
  ) {
    final index = <int, List<Creator>>{};
    for (final creator in creators) {
      final seen = <int>{};
      for (final fandom in creator.fandoms) {
        var current = fandom.id;
        for (var depth = 0; depth < 8 && seen.add(current); depth++) {
          index.putIfAbsent(current, () => []).add(creator);
          final parent = fandomById[current]?.parentId;
          if (parent == null) break;
          current = parent;
        }
      }
    }
    return index;
  }

  ({double affinity, int tier, List<String> matchingFandoms}) _fandomAffinity(
    Creator creator,
    Map<int, double> interestVector,
    _FandomCatalog catalog,
    int creatorCount,
  ) {
    final matches = <({String fandom, double value, int tier})>[];
    for (final fandom in catalog.entriesByCreatorId[creator.id] ?? const []) {
      var best = 0.0;
      var tier = 0;
      for (final entry in interestVector.entries) {
        final relation = _fandomRelation(fandom.id, entry.key, catalog);
        final value = entry.value * relation.value;
        if (value > best) {
          best = value;
          tier = relation.tier;
        }
      }
      if (best <= 0) continue;
      final frequency = catalog.documentFrequency[fandom.id] ?? 1;
      final specificity =
          (log((creatorCount + 1) / (frequency + 1)) / 4).clamp(0.7, 1.0);
      matches.add((fandom: fandom.name, value: best * specificity, tier: tier));
    }
    matches.sort((a, b) => b.value.compareTo(a.value));

    var affinity = 0.0;
    if (matches.isNotEmpty) affinity += matches[0].value;
    if (matches.length > 1) affinity += matches[1].value * 0.4;
    if (matches.length > 2) affinity += matches[2].value * 0.2;

    return (
      affinity: (affinity / 1.45).clamp(0.0, 1.0),
      tier:
          matches.isEmpty ? 0 : matches.map((match) => match.tier).reduce(max),
      matchingFandoms: matches.take(3).map((match) => match.fandom).toList(),
    );
  }

  ({double value, int tier}) _fandomRelation(
    int candidateId,
    int interestId,
    _FandomCatalog catalog,
  ) {
    if (catalog.relations.length >= 100000) catalog.relations.clear();
    return catalog.relations.putIfAbsent((candidateId, interestId),
        () => _uncachedFandomRelation(candidateId, interestId, catalog));
  }

  ({double value, int tier}) _uncachedFandomRelation(
    int candidateId,
    int interestId,
    _FandomCatalog catalog,
  ) {
    if (candidateId == interestId) {
      final kind = catalog.fandomById[candidateId]?.kind;
      return kind == 'publisher_umbrella'
          ? (value: 0.55, tier: 1)
          : (value: 1, tier: 3);
    }
    final candidateAncestors = _ancestors(candidateId, catalog);
    final interestAncestors = _ancestors(interestId, catalog);
    var best = 0.0;
    var bestTier = 0;
    for (final entry in candidateAncestors.entries) {
      final otherDistance = interestAncestors[entry.key];
      if (otherDistance == null) continue;
      final kind = catalog.fandomById[entry.key]?.kind;
      final tier = kind == 'franchise'
          ? 2
          : kind == 'publisher_umbrella' || kind == null
              ? 1
              : 0;
      if (tier == 0) continue;
      final base = tier == 2 ? 0.58 : 0.30;
      final distance = entry.value + otherDistance;
      final value = base * pow(0.82, max(0, distance - 1));
      if (value > best) {
        best = value.toDouble();
        bestTier = tier;
      }
    }
    return (value: best, tier: bestTier);
  }

  Map<int, int> _ancestors(int fandomId, _FandomCatalog catalog) {
    return catalog.ancestors.putIfAbsent(fandomId, () {
      final result = <int, int>{};
      var current = fandomId;
      for (var distance = 0; distance < 8; distance++) {
        if (result.containsKey(current)) break;
        result[current] = distance;
        final parent = catalog.fandomById[current]?.parentId;
        if (parent == null) break;
        current = parent;
      }
      return result;
    });
  }

  List<({Creator creator, double strength})> _buildItineraryAnchors({
    required Map<int, Creator> creatorsById,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
  }) {
    final anchors = <({Creator creator, double strength})>[];
    for (final creator in creatorsById.values) {
      final interaction = profile.creatorInteractions[creator.id];
      final strength = favoriteIds.contains(creator.id)
          ? 1.0
          : interaction?.consideration ?? 0;
      if (strength >= 0.2 && creator.booths.isNotEmpty) {
        anchors.add((creator: creator, strength: strength.clamp(0.0, 1.0)));
      }
    }
    anchors.sort((a, b) => b.strength.compareTo(a.strength));
    final favoriteAnchors =
        anchors.where((a) => favoriteIds.contains(a.creator.id));
    final otherAnchors =
        anchors.where((a) => !favoriteIds.contains(a.creator.id));
    return [...favoriteAnchors, ...otherAnchors.take(20)];
  }

  Map<int, ({double affinity, List<int> nearbyCreatorIds})> _nearbyAffinities(
    List<({Creator creator, double strength})> anchors,
    _FandomCatalog catalog,
  ) {
    final result = <int, ({double affinity, List<int> nearbyCreatorIds})>{};
    for (final anchor in anchors) {
      for (final sourceBooth in anchor.creator.booths) {
        final normalized = BoothProximityData.canonicalBooth(sourceBooth);
        final neighbors = <String, int>{
          normalized: 0,
          ...boothProximity.neighborsOf(sourceBooth),
        };
        for (final entry in neighbors.entries) {
          final affinity =
              anchor.strength * exp(-entry.value / _walkingDistanceScale);
          for (final candidate
              in catalog.creatorsByBooth[entry.key] ?? const <Creator>[]) {
            if (candidate.id == anchor.creator.id ||
                !candidate.attendanceDates.any(
                    (day) => anchor.creator.attendanceDates.contains(day))) {
              continue;
            }
            final current = result[candidate.id];
            if (current == null || affinity > current.affinity) {
              result[candidate.id] = (
                affinity: affinity,
                nearbyCreatorIds: [anchor.creator.id],
              );
            } else if (affinity >= current.affinity * 0.8 &&
                !current.nearbyCreatorIds.contains(anchor.creator.id) &&
                current.nearbyCreatorIds.length < 3) {
              current.nearbyCreatorIds.add(anchor.creator.id);
            }
          }
        }
      }
    }
    return result;
  }

  List<RecommendationResult> _selectDiverse(
    List<RecommendationResult> candidates,
    int limit, {
    required int userSeed,
    required Set<int> previousIds,
  }) {
    if (candidates.isEmpty) return [];
    final ranked = List<RecommendationResult>.from(candidates)
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : a.creator.id.compareTo(b.creator.id);
      });
    final cutoff = ranked.first.score * 0.6;
    final strong =
        ranked.where((candidate) => candidate.score >= cutoff).toList();
    final remaining = strong.length >= limit ? strong : ranked;
    final selected = <RecommendationResult>[];
    for (var i = 0; i < min(2, limit) && remaining.isNotEmpty; i++) {
      selected.add(remaining.removeAt(0));
    }
    final random = Random(userSeed);
    final represented = <String>{
      for (final result in selected) ...result.matchingFandoms,
    };
    while (remaining.isNotEmpty && selected.length < limit) {
      var total = 0.0;
      final weights = <double>[];
      for (final candidate in remaining) {
        final relative = candidate.score / ranked.first.score;
        final coverage = candidate.matchingFandoms.any(
          (name) => !represented.contains(name),
        )
            ? 1.15
            : 1.0;
        final retention =
            previousIds.contains(candidate.creator.id) ? 1.2 : 1.0;
        final weight = pow(relative, 4).toDouble() * coverage * retention;
        weights.add(weight);
        total += weight;
      }
      var draw = random.nextDouble() * total;
      var chosen = remaining.length - 1;
      for (var i = 0; i < weights.length; i++) {
        draw -= weights[i];
        if (draw <= 0) {
          chosen = i;
          break;
        }
      }
      final picked = remaining.removeAt(chosen);
      selected.add(picked);
      represented.addAll(picked.matchingFandoms);
    }
    return selected;
  }

  Future<List<RecommendationResult>> _selectDiverseAsync(
    List<RecommendationResult> candidates,
    int limit, {
    required _AsyncBudget budget,
    required int userSeed,
    required Set<int> previousIds,
    bool Function()? isCancelled,
  }) async {
    await budget.checkpoint(force: true);
    if (isCancelled?.call() ?? false) return [];
    return _selectDiverse(candidates, limit,
        userSeed: userSeed, previousIds: previousIds);
  }

  double _decay(
    double value,
    DateTime lastUpdated,
    Duration halfLife,
    DateTime now,
  ) {
    if (lastUpdated.millisecondsSinceEpoch <= 0 || !now.isAfter(lastUpdated)) {
      return value;
    }
    final elapsed = now.difference(lastUpdated).inMilliseconds;
    final periods = elapsed / halfLife.inMilliseconds;
    return value * pow(0.5, periods);
  }
}

class _FandomCatalog {
  final Map<int, Fandom> sourceRegistry;
  final Map<int, int> documentFrequency;
  final Map<int, List<Fandom>> entriesByCreatorId;
  final Map<int, String> displayById;
  final Map<int, Fandom> fandomById;
  final Map<String, List<Creator>> creatorsByBooth;
  final Map<int, List<Creator>> creatorsByAncestor;
  final Map<int, Map<int, int>> ancestors = {};
  final Map<(int, int), ({double value, int tier})> relations = {};

  _FandomCatalog({
    required this.sourceRegistry,
    required this.documentFrequency,
    required this.entriesByCreatorId,
    required this.displayById,
    required this.fandomById,
    required this.creatorsByBooth,
    required this.creatorsByAncestor,
  });
}

class _AsyncBudget {
  Stopwatch _stopwatch = Stopwatch()..start();

  Future<void> checkpoint({bool force = false}) async {
    if (!force && _stopwatch.elapsedMicroseconds < 3000) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _stopwatch = Stopwatch()..start();
  }
}
