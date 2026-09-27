import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/creator.dart';
import '../models/fandom.dart';
import '../utils/browser_navigation.dart';
import 'catalog_snapshot_cache.dart';
import 'creator_catalog_index.dart';
import 'version_service.dart';

enum CreatorDataStatus { idle, loading, updating, updated, error }

class CreatorDataProvider extends ChangeNotifier {
  static final Uri _configBase = Uri.parse('https://cp7-config.wibuvent.com/');
  static const String _bundledCatalog = 'data/catalog-initial.json';
  static const String _bundledFandoms = 'data/fandoms-initial.json';
  static const String _bundledVersion = 'data/last-updated-initial.json';

  final bool enableRemoteUpdates;
  final CatalogSnapshotCache _snapshotCache;

  CreatorDataProvider({
    this.enableRemoteUpdates = true,
    CatalogSnapshotCache? snapshotCache,
  }) : _snapshotCache = snapshotCache ?? CatalogSnapshotCache();

  List<Creator>? _allCreators;
  Map<int, Fandom> _fandomById = const {};
  CreatorCatalogIndex? _fullIndex;
  CreatorCatalogIndex? _customIndex;
  int? _currentDataVersion;
  bool _isLoading = true;
  String? _error;
  CreatorDataStatus _status = CreatorDataStatus.idle;
  Timer? _updateTimer;
  Creator? _selectedCreator;
  List<int>? _customCreatorIds;
  bool _showAddAllToFavorites = true;
  bool _shouldRefreshOnReturn = true;
  VoidCallback? _onInitialized;

  CreatorCatalogIndex? get _activeIndex => _customIndex ?? _fullIndex;
  List<Creator>? get creators => _activeIndex?.creators;
  int? get currentDataVersion => _currentDataVersion;
  Map<String, List<Creator>>? get boothToCreators =>
      _activeIndex?.creatorsByBooth;
  Map<int, Fandom> get fandomById => _fandomById;
  bool get isLoading => _isLoading;
  String? get error => _error;
  CreatorDataStatus get status => _status;
  Creator? get selectedCreator => _selectedCreator;
  List<Creator>? get creatorCustomList => _customIndex?.creators;
  bool get isCreatorCustomListMode => _customCreatorIds != null;
  bool get showAddAllToFavorites => _showAddAllToFavorites;
  bool get shouldRefreshOnReturn => _shouldRefreshOnReturn;
  List<String> get popularSearches =>
      _activeIndex?.popularFandomNames() ?? const [];

  void onCreatorDataServiceInitialized(VoidCallback callback) {
    _onInitialized = callback;
    if (!_isLoading) callback();
  }

  void setSelectedCreator(Creator? creator) {
    _selectedCreator = creator;
    notifyListeners();
  }

  Creator? selectRandomCreator() {
    final current = creators;
    if (current == null || current.isEmpty) return null;
    final creator = current[Random().nextInt(current.length)];
    setSelectedCreator(creator);
    return creator;
  }

  Creator? getCreatorById(int id) => _fullIndex?.creatorById[id];

  int? fandomIdForName(String name) => _fullIndex?.fandomIdForName(name);

  List<Creator> searchCreators(String query) =>
      _activeIndex?.search(query) ?? const [];

  List<String> fandomSuggestions(String query, {int limit = 20}) =>
      _activeIndex?.fandomSuggestions(query, limit: limit) ?? const [];

  List<String> matchingFandomNames(String query, {int limit = 20}) =>
      _activeIndex?.matchingFandomNames(query, limit: limit) ?? const [];

  void setCreatorCustomList(
    List<int> creatorIds, {
    bool showAddAllToFavorites = true,
    bool shouldRefreshOnReturn = true,
  }) {
    _customCreatorIds = List.unmodifiable(creatorIds);
    _showAddAllToFavorites = showAddAllToFavorites;
    _shouldRefreshOnReturn = shouldRefreshOnReturn;
    _rebuildCustomIndex();
    notifyListeners();
  }

  void clearCreatorCustomList() {
    _customCreatorIds = null;
    _customIndex = null;
    _showAddAllToFavorites = true;
    _shouldRefreshOnReturn = true;
    if (kIsWeb) browserPushState('/');
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      _setLoading(true);
      _setError(null);
      final bundledVersion = await _loadBundledVersion();
      final cached = await _loadCachedSnapshot();
      final usableCache =
          cached != null && cached.version >= bundledVersion ? cached : null;
      final snapshot =
          usableCache ?? await _loadBundledSnapshot(version: bundledVersion);
      _applySnapshot(snapshot);
      if (usableCache == null) await _cacheSnapshot(snapshot);
      if (enableRemoteUpdates) _startPeriodicUpdateCheck();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print('Could not initialize creator catalog: $error\n$stackTrace');
      }
      _setError(error.toString());
    } finally {
      _setLoading(false);
      _onInitialized?.call();
    }
  }

  void _startPeriodicUpdateCheck() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _checkForUpdates(),
    );
    unawaited(_checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    try {
      final remote = await VersionService.fetchVersionInfo();
      if (remote == null) return;
      if (_currentDataVersion != null &&
          remote.creatorDataVersion <= _currentDataVersion!) {
        return;
      }

      _setStatus(CreatorDataStatus.updating);
      final snapshot = await _fetchRemoteSnapshot(remote.creatorDataVersion);
      _applySnapshot(snapshot);
      await _cacheSnapshot(snapshot);
      _setStatus(CreatorDataStatus.updated);
    } catch (error) {
      if (kDebugMode) print('Could not update creator catalog: $error');
      _setStatus(CreatorDataStatus.error);
    }
  }

  Future<int> _loadBundledVersion() async {
    final raw = await rootBundle.loadString(_bundledVersion);
    return ((json.decode(raw) as Map)['creator_data_version'] as num).toInt();
  }

  Future<_CatalogSnapshot> _loadBundledSnapshot({required int version}) async {
    final values = await Future.wait([
      rootBundle.loadString(_bundledCatalog),
      rootBundle.loadString(_bundledFandoms),
    ]);
    return _CatalogSnapshot.fromJson(
      version: version,
      catalog: json.decode(values[0]) as Map<String, dynamic>,
      fandomRegistry: json.decode(values[1]) as Map<String, dynamic>,
    );
  }

  Future<_CatalogSnapshot?> _loadCachedSnapshot() async {
    try {
      final raw = await _snapshotCache.read();
      if (raw == null) return null;
      final data = json.decode(raw) as Map<String, dynamic>;
      return _CatalogSnapshot.fromJson(
        version: (data['version'] as num).toInt(),
        catalog: Map<String, dynamic>.from(data['catalog'] as Map),
        fandomRegistry:
            Map<String, dynamic>.from(data['fandomRegistry'] as Map),
      );
    } catch (error) {
      if (kDebugMode) print('Ignoring invalid cached catalog: $error');
      return null;
    }
  }

  Future<_CatalogSnapshot> _fetchRemoteSnapshot(int version) async {
    final manifest = await _fetchJson(_configBase.resolve('manifest.json'));
    _requireSchemaV1(manifest, 'manifest');
    final catalogPath = manifest['catalog']?.toString();
    final fandomPath = manifest['fandomRegistry']?.toString();
    if (catalogPath == null || fandomPath == null) {
      throw const FormatException('Manifest is missing catalog paths');
    }
    final documents = await Future.wait([
      _fetchJson(_configBase.resolve(catalogPath)),
      _fetchJson(_configBase.resolve(fandomPath)),
    ]);
    return _CatalogSnapshot.fromJson(
      version: version,
      catalog: documents[0],
      fandomRegistry: documents[1],
    );
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final requestUri = uri.replace(queryParameters: {
      ...uri.queryParameters,
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final response = await http.get(requestUri).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode != 200) {
      throw StateError('${uri.path} returned HTTP ${response.statusCode}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  void _applySnapshot(_CatalogSnapshot snapshot) {
    final sortedCreators = List<Creator>.from(snapshot.creators)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _allCreators = List.unmodifiable(sortedCreators);
    _fandomById = Map.unmodifiable(snapshot.fandomById);
    _currentDataVersion = snapshot.version;
    _fullIndex = CreatorCatalogIndex.build(_allCreators!, _fandomById);
    _rebuildCustomIndex();
    if (_selectedCreator != null) {
      _selectedCreator = _fullIndex!.creatorById[_selectedCreator!.id];
    }
    notifyListeners();
  }

  void _rebuildCustomIndex() {
    final ids = _customCreatorIds;
    final full = _fullIndex;
    if (ids == null || full == null) {
      _customIndex = null;
      return;
    }
    final selected = ids.map((id) => full.creatorById[id]).nonNulls.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _customIndex = CreatorCatalogIndex.build(
      List.unmodifiable(selected),
      _fandomById,
    );
  }

  Future<void> _cacheSnapshot(_CatalogSnapshot snapshot) async {
    await _snapshotCache.write(json.encode(snapshot.toJson()));
  }

  Future<void> clearCache() => _snapshotCache.clear();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _setStatus(CreatorDataStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}

class _CatalogSnapshot {
  final int version;
  final Map<String, dynamic> catalog;
  final Map<String, dynamic> fandomRegistry;
  final Map<int, Fandom> fandomById;
  final List<Creator> creators;

  _CatalogSnapshot._({
    required this.version,
    required this.catalog,
    required this.fandomRegistry,
    required this.fandomById,
    required this.creators,
  });

  factory _CatalogSnapshot.fromJson({
    required int version,
    required Map<String, dynamic> catalog,
    required Map<String, dynamic> fandomRegistry,
  }) {
    _requireSchemaV1(catalog, 'catalog');
    _requireSchemaV1(fandomRegistry, 'fandom registry');
    final fandoms = ((fandomRegistry['fandoms'] as List?) ?? const [])
        .whereType<Map>()
        .map((data) => Fandom.fromJson(Map<String, dynamic>.from(data)))
        .toList(growable: false);
    final fandomById = {for (final fandom in fandoms) fandom.id: fandom};
    final event = Map<String, dynamic>.from(catalog['event'] as Map);
    final dayLabels = <String, String>{
      for (final day in ((event['days'] as List?) ?? const []).whereType<Map>())
        day['id'].toString(): day['label'].toString(),
    };
    final creators = ((catalog['exhibitors'] as List?) ?? const [])
        .whereType<Map>()
        .map((data) => Creator.fromCatalogJson(
              Map<String, dynamic>.from(data),
              fandomById: fandomById,
              dayLabels: dayLabels,
            ))
        .toList(growable: false);
    return _CatalogSnapshot._(
      version: version,
      catalog: catalog,
      fandomRegistry: fandomRegistry,
      fandomById: fandomById,
      creators: creators,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'catalog': catalog,
        'fandomRegistry': fandomRegistry,
      };
}

void _requireSchemaV1(Map<String, dynamic> data, String document) {
  final schema = data['schemaVersion']?.toString();
  if (schema == null || !schema.startsWith('1.')) {
    throw FormatException('Unsupported $document schema: $schema');
  }
}
