import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/booth_proximity.dart';
import '../models/creator.dart';
import '../models/fandom.dart';
import '../models/recommendation.dart';
import '../utils/string_utils.dart';
import 'recommendation_engine.dart';

class RecommendationService extends ChangeNotifier {
  static const String _storageKey = 'cp7_recommendation_profile_v2';
  static const String _resultStorageKey = 'cp7_recommendation_results_v5';
  static const String _seedStorageKey = 'cp7_recommendation_seed';
  static const int _algorithmVersion = 5;
  static const Duration _saveDelay = Duration(milliseconds: 500);
  static Future<BoothProximityData>? _boothProximityLoad;

  final bool disabled;
  final Duration refreshDelay;

  RecommendationProfile _profile = RecommendationProfile();
  RecommendationEngine _engine = const RecommendationEngine();
  List<RecommendationResult>? _cachedRecommendations;
  List<RecommendationResult>? _visibleRecommendations;
  Map<String, dynamic>? _savedResult;
  int _userSeed = 0;
  bool _homeVisible = false;
  bool _homeJustBecameVisible = false;
  DateTime? _lastCalculationFinished;
  List<String>? _cachedHomeFandomSuggestions;
  List<String>? _visibleHomeFandomSuggestions;
  ({
    int creators,
    int favorites,
    int profile,
    int popular,
    int limit,
  })? _cachedHomeFandomKey;
  ({int creators, int favorites, int limit, int revision})? _cachedRequestKey;
  ({int creators, int favorites, int limit, int revision})? _desiredRequestKey;
  _RecommendationRequest? _pendingRequest;
  _RecommendationRequest? _lastRequest;
  bool _refreshRunning = false;
  int _generation = 0;
  int _sessionRevision = 0;
  Timer? _saveTimer;
  Timer? _refreshTimer;
  bool _initialized = false;
  bool _disposed = false;

  RecommendationService({
    this.disabled = false,
    this.refreshDelay = const Duration(seconds: 30),
  });

  RecommendationProfile get profile => _profile;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (disabled) {
      _initialized = true;
      return;
    }
    try {
      final boothProximity = await _loadBoothProximity();
      _engine = RecommendationEngine(boothProximity: boothProximity);
    } catch (error) {
      if (kDebugMode) {
        print('Could not load booth proximity data: $error');
      }
    }
    await _loadProfile();
    await _loadSavedResultAndSeed();
    _initialized = true;
    notifyListeners();
  }

  static Future<BoothProximityData> _loadBoothProximity() =>
      _boothProximityLoad ??= _readBoothProximity();

  static Future<BoothProximityData> _readBoothProximity() async {
    final raw = await rootBundle.loadString('data/booth-proximity.json');
    return BoothProximityData.fromJson(
      json.decode(raw) as Map<String, dynamic>,
    );
  }

  List<RecommendationResult> recommendationsFor({
    required List<Creator> creators,
    required Set<int> favoriteIds,
    Map<int, Fandom> allFandoms = const {},
    int catalogVersion = 0,
    int limit = 10,
  }) {
    if (disabled || !_initialized) {
      return const [];
    }

    final creatorSignature = Object.hash(
      identityHashCode(creators),
      creators.length,
    );
    final sortedFavorites = favoriteIds.toList()..sort();
    final favoriteSignature = Object.hashAll(sortedFavorites);
    final requestKey = (
      creators: creatorSignature,
      favorites: favoriteSignature,
      limit: limit,
      revision: _sessionRevision,
    );
    _lastRequest = _RecommendationRequest(
      key: requestKey,
      generation: _generation,
      creators: creators,
      favoriteIds: Set<int>.of(favoriteIds),
      limit: limit,
      catalogVersion: catalogVersion,
      allFandoms: allFandoms,
    );

    if (!_hasRecommendationData(favoriteIds)) return const [];

    _restoreSavedResult(_lastRequest!);

    if (_cachedRequestKey != requestKey && _desiredRequestKey != requestKey) {
      _queueRefresh(_lastRequest!);
    }

    if (_homeVisible && _visibleRecommendations == null) {
      _visibleRecommendations = _cachedRecommendations;
    }
    return _compatibleCachedRecommendations(
      requestKey,
      favoriteIds: favoriteIds,
    );
  }

  void setHomeVisible(bool visible) {
    if (visible && !_homeVisible) {
      _homeJustBecameVisible = true;
      _visibleRecommendations =
          _cachedRecommendations ?? _visibleRecommendations;
      _visibleHomeFandomSuggestions =
          _cachedHomeFandomSuggestions ?? _visibleHomeFandomSuggestions;
    }
    _homeVisible = visible;
  }

  List<String> homeFandomSuggestionsFor({
    required List<Creator> creators,
    required Set<int> favoriteIds,
    required List<String> popularFandoms,
    Map<int, Fandom> allFandoms = const {},
    int limit = 20,
  }) {
    if (limit <= 0) return const [];

    final sortedFavorites = favoriteIds.toList()..sort();
    final key = (
      creators: Object.hash(identityHashCode(creators), creators.length),
      favorites: Object.hashAll(sortedFavorites),
      profile: _generation,
      popular: Object.hashAll(popularFandoms),
      limit: limit,
    );
    if (_cachedHomeFandomKey == key) {
      if (_homeJustBecameVisible) {
        _visibleHomeFandomSuggestions = _cachedHomeFandomSuggestions;
        _homeJustBecameVisible = false;
      }
      return _homeVisible
          ? (_visibleHomeFandomSuggestions ??
              _cachedHomeFandomSuggestions ??
              const [])
          : (_cachedHomeFandomSuggestions ?? const []);
    }

    final interestedFandoms = disabled || !_initialized
        ? const <String>[]
        : _engine.rankedInterestedFandoms(
            creators: creators,
            profile: _profile,
            favoriteIds: favoriteIds,
            allFandoms: allFandoms,
          );
    final suggestions = <String>[];
    final normalizedSuggestions = <String>{};
    for (final fandom in [...interestedFandoms, ...popularFandoms]) {
      final normalized = optimizeStringFormat(fandom);
      if (normalized.isEmpty || !normalizedSuggestions.add(normalized)) {
        continue;
      }
      suggestions.add(fandom);
      if (suggestions.length == limit) break;
    }

    _cachedHomeFandomKey = key;
    _cachedHomeFandomSuggestions = List.unmodifiable(suggestions);
    if (_homeJustBecameVisible) {
      _visibleHomeFandomSuggestions = _cachedHomeFandomSuggestions;
      _homeJustBecameVisible = false;
    }
    _visibleHomeFandomSuggestions ??= _cachedHomeFandomSuggestions;
    return _homeVisible
        ? _visibleHomeFandomSuggestions!
        : _cachedHomeFandomSuggestions!;
  }

  Future<void> _processPendingRefresh() async {
    if (disabled || _refreshRunning || _disposed) return;
    final request = _pendingRequest;
    if (request == null) return;

    _pendingRequest = null;
    _refreshRunning = true;
    final profileSnapshot = RecommendationProfile.fromJson(_profile.toJson());
    final previousIds = {
      for (final result
          in _visibleRecommendations ?? const <RecommendationResult>[])
        result.creator.id,
    };
    final results = await _engine.recommendAsync(
      creators: request.creators,
      profile: profileSnapshot,
      favoriteIds: request.favoriteIds,
      allFandoms: request.allFandoms,
      sessionExposureIds: const {},
      userSeed: _userSeed,
      previousIds: previousIds,
      limit: request.limit,
      isCancelled: () => _disposed || request.generation != _generation,
    );
    _refreshRunning = false;
    _lastCalculationFinished = DateTime.now();

    if (!_disposed &&
        request.generation == _generation &&
        request.key == _desiredRequestKey) {
      _cachedRecommendations = results;
      _cachedRequestKey = request.key;
      if (_visibleRecommendations == null) {
        _visibleRecommendations = results;
        notifyListeners();
      }
      unawaited(_saveResult(request, results));
    }

    if (_pendingRequest != null && !_disposed) {
      _schedulePendingCalculation();
    }
  }

  void recordCreatorOpened(
    Creator creator,
    CreatorSelectionSource source,
  ) {
    if (disabled) return;
    if (source == CreatorSelectionSource.mapTap ||
        source == CreatorSelectionSource.randomButton) {
      return;
    }

    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    if (interaction.deliberateOpenCount > 0 &&
        now.difference(interaction.lastUpdated) < const Duration(minutes: 30)) {
      return;
    }
    final (openStrength, consideration) = switch (source) {
      CreatorSelectionSource.deepLink => (2.5, 0.30),
      CreatorSelectionSource.searchResult => (2.0, 0.20),
      CreatorSelectionSource.allCreators => (1.5, 0.10),
      CreatorSelectionSource.customList => (1.0, 0.10),
      CreatorSelectionSource.recommendation => (0.5, 0.10),
      CreatorSelectionSource.favorites => (0.5, 1.00),
      CreatorSelectionSource.mapTap || CreatorSelectionSource.randomButton => (
          0.0,
          0.0
        ),
    };

    interaction.openStrength =
        (interaction.openStrength + openStrength).clamp(0.0, 6.0);
    interaction.deliberateOpenCount =
        (interaction.deliberateOpenCount + 1).clamp(0, 5);
    interaction.consideration = interaction.consideration < consideration
        ? consideration
        : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  void recordFandomInterest(int fandomId) {
    if (disabled) return;

    final now = DateTime.now();
    final signal = _profile.explicitFandomSignals.putIfAbsent(
      fandomId,
      () => FandomSignal(strength: 0, lastUpdated: now),
    );
    signal.strength = (signal.strength + 5).clamp(0.0, 20.0);
    signal.lastUpdated = now;
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  void recordSampleWorksViewed(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.sampleWorkViews = (interaction.sampleWorkViews + 1).clamp(0, 3);
    interaction.consideration =
        interaction.consideration < 0.5 ? 0.5 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  void recordExternalLinkOpened(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.externalLinkClicks =
        (interaction.externalLinkClicks + 1).clamp(0, 2);
    interaction.consideration =
        interaction.consideration < 0.6 ? 0.6 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  void recordCreatorShared(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.shares = (interaction.shares + 1).clamp(0, 2);
    interaction.consideration =
        interaction.consideration < 0.7 ? 0.7 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  void recordFavoriteChanged(Creator creator, bool favorite) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.favorite = favorite;
    interaction.consideration =
        favorite ? 1.0 : _considerationWithoutFavorite(interaction);
    interaction.lastUpdated = now;
    final lastRequest = _lastRequest;
    if (lastRequest != null) {
      final favoriteIds = Set<int>.of(lastRequest.favoriteIds);
      if (favorite) {
        favoriteIds.add(creator.id);
      } else {
        favoriteIds.remove(creator.id);
      }
      _lastRequest = _requestWithFavorites(lastRequest, favoriteIds);
    }
    _scheduleSave();
    _scheduleRecommendationRefresh();
  }

  Future<void> clearProfile() async {
    if (disabled) return;
    _profile = RecommendationProfile();
    _saveTimer?.cancel();
    _refreshTimer?.cancel();
    _generation++;
    _cachedRecommendations = null;
    _visibleRecommendations = null;
    _savedResult = null;
    _cachedRequestKey = null;
    _cachedHomeFandomSuggestions = null;
    _visibleHomeFandomSuggestions = null;
    _cachedHomeFandomKey = null;
    _desiredRequestKey = null;
    _pendingRequest = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    await preferences.remove(_resultStorageKey);
    notifyListeners();
  }

  CreatorInteraction _interactionFor(int creatorId, DateTime now) {
    return _profile.creatorInteractions.putIfAbsent(
      creatorId,
      () => CreatorInteraction(lastUpdated: now),
    );
  }

  double _considerationWithoutFavorite(CreatorInteraction interaction) {
    if (interaction.shares > 0) return 0.7;
    if (interaction.externalLinkClicks > 0) return 0.6;
    if (interaction.sampleWorkViews > 0) return 0.5;
    if (interaction.deliberateOpenCount >= 2) return 0.25;
    if (interaction.deliberateOpenCount == 1) return 0.1;
    return 0;
  }

  Future<void> _loadProfile() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null) return;
      _profile = RecommendationProfile.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );
    } catch (error) {
      if (kDebugMode) {
        print('Could not load recommendation profile: $error');
      }
      _profile = RecommendationProfile();
    }
  }

  Future<void> _loadSavedResultAndSeed() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedSeed = preferences.getInt(_seedStorageKey);
      _userSeed = savedSeed ?? Random().nextInt(0x7fffffff);
      if (savedSeed == null) {
        await preferences.setInt(_seedStorageKey, _userSeed);
      }
      final raw = preferences.getString(_resultStorageKey);
      if (raw != null) _savedResult = json.decode(raw) as Map<String, dynamic>;
    } catch (error) {
      if (kDebugMode) print('Could not load saved recommendations: $error');
      _userSeed = Random().nextInt(0x7fffffff);
    }
  }

  String _resultFingerprint(_RecommendationRequest request) {
    final favorites = request.favoriteIds.toList()..sort();
    return json.encode({
      'algorithm': _algorithmVersion,
      'catalog': request.catalogVersion,
      'map': _engine.boothProximity.mapSha256,
      'day': DateTime.now().toUtc().toIso8601String().substring(0, 10),
      'favorites': favorites,
      'limit': request.limit,
      'profile': _profile.toJson(),
    });
  }

  void _restoreSavedResult(_RecommendationRequest request) {
    if (_cachedRecommendations != null || _savedResult == null) return;
    final saved = _savedResult!;
    if (saved['fingerprint'] != _resultFingerprint(request)) return;
    final creatorsById = {
      for (final creator in request.creators) creator.id: creator,
    };
    final results = <RecommendationResult>[];
    for (final raw in (saved['results'] as List?) ?? const []) {
      if (raw is! Map) return;
      final value = Map<String, dynamic>.from(raw);
      final creator = creatorsById[(value['id'] as num?)?.toInt()];
      if (creator == null) return;
      results.add(RecommendationResult(
        creator: creator,
        score: (value['score'] as num?)?.toDouble() ?? 0,
        fandomAffinity: (value['fandom'] as num?)?.toDouble() ?? 0,
        itineraryAffinity: (value['nearby'] as num?)?.toDouble() ?? 0,
        matchingFandoms: ((value['matches'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        nearbyPlannedCreatorIds: ((value['anchors'] as List?) ?? const [])
            .whereType<num>()
            .map((item) => item.toInt())
            .toList(),
        matchTier: (value['tier'] as num?)?.toInt() ?? 0,
      ));
    }
    _cachedRecommendations = results;
    _cachedRequestKey = request.key;
    _visibleRecommendations ??= results;
  }

  Future<void> _saveResult(
    _RecommendationRequest request,
    List<RecommendationResult> results,
  ) async {
    try {
      final data = <String, dynamic>{
        'fingerprint': _resultFingerprint(request),
        'results': [
          for (final result in results)
            {
              'id': result.creator.id,
              'score': result.score,
              'fandom': result.fandomAffinity,
              'nearby': result.itineraryAffinity,
              'matches': result.matchingFandoms,
              'anchors': result.nearbyPlannedCreatorIds,
              'tier': result.matchTier,
            },
        ],
      };
      _savedResult = data;
      final preferences = await SharedPreferences.getInstance();
      if (_disposed || request.generation != _generation) return;
      await preferences.setString(_resultStorageKey, json.encode(data));
    } catch (error) {
      if (kDebugMode) print('Could not save recommendations: $error');
    }
  }

  void _scheduleSave() {
    if (disabled) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveProfile);
  }

  void _scheduleRecommendationRefresh() {
    if (disabled) return;
    _generation++;
    _sessionRevision++;
    _desiredRequestKey = null;
    _pendingRequest = null;
    final lastRequest = _lastRequest;
    if (lastRequest != null &&
        _hasRecommendationData(lastRequest.favoriteIds)) {
      _queueRefresh(lastRequest);
    }
  }

  void _queueRefresh(_RecommendationRequest source) {
    final sortedFavorites = source.favoriteIds.toList()..sort();
    final key = (
      creators: Object.hash(
        identityHashCode(source.creators),
        source.creators.length,
      ),
      favorites: Object.hashAll(sortedFavorites),
      limit: source.limit,
      revision: _sessionRevision,
    );
    if (_cachedRequestKey == key || _desiredRequestKey == key) return;

    _generation++;
    _desiredRequestKey = key;
    _pendingRequest = _RecommendationRequest(
      key: key,
      generation: _generation,
      creators: source.creators,
      favoriteIds: Set<int>.of(source.favoriteIds),
      limit: source.limit,
      catalogVersion: source.catalogVersion,
      allFandoms: source.allFandoms,
    );
    _schedulePendingCalculation();
  }

  void _schedulePendingCalculation() {
    if (_refreshRunning || _pendingRequest == null || _disposed) return;
    _refreshTimer?.cancel();
    final earliest = _lastCalculationFinished?.add(refreshDelay);
    final delay =
        earliest == null ? Duration.zero : earliest.difference(DateTime.now());
    _refreshTimer =
        Timer(delay.isNegative ? Duration.zero : delay, _processPendingRefresh);
  }

  _RecommendationRequest _requestWithFavorites(
    _RecommendationRequest source,
    Set<int> favoriteIds,
  ) {
    return _RecommendationRequest(
      key: source.key,
      generation: source.generation,
      creators: source.creators,
      favoriteIds: favoriteIds,
      limit: source.limit,
      catalogVersion: source.catalogVersion,
      allFandoms: source.allFandoms,
    );
  }

  bool _hasRecommendationData(Set<int> favoriteIds) {
    if (favoriteIds.isNotEmpty || _profile.explicitFandomSignals.isNotEmpty) {
      return true;
    }
    return _profile.creatorInteractions.values.any(
      (interaction) =>
          interaction.openStrength > 0 ||
          interaction.sampleWorkViews > 0 ||
          interaction.externalLinkClicks > 0 ||
          interaction.shares > 0 ||
          interaction.favorite,
    );
  }

  List<RecommendationResult> _compatibleCachedRecommendations(
    ({
      int creators,
      int favorites,
      int limit,
      int revision,
    }) requestKey, {
    required Set<int> favoriteIds,
  }) {
    final cached = _visibleRecommendations;
    if (cached == null) {
      return const [];
    }
    return cached
        .where((result) => !favoriteIds.contains(result.creator.id))
        .take(requestKey.limit)
        .toList();
  }

  Future<void> _saveProfile() async {
    if (disabled) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, json.encode(_profile.toJson()));
    } catch (error) {
      if (kDebugMode) {
        print('Could not save recommendation profile: $error');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _saveTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class _RecommendationRequest {
  final ({
    int creators,
    int favorites,
    int limit,
    int revision,
  }) key;
  final int generation;
  final List<Creator> creators;
  final Set<int> favoriteIds;
  final int limit;
  final int catalogVersion;
  final Map<int, Fandom> allFandoms;

  const _RecommendationRequest({
    required this.key,
    required this.generation,
    required this.creators,
    required this.favoriteIds,
    required this.limit,
    required this.catalogVersion,
    required this.allFandoms,
  });
}
