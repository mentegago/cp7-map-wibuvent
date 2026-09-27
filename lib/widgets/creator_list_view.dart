import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:cf_map_flutter/services/favorites_service.dart';
import 'package:cf_map_flutter/widgets/creator_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/creator.dart';
import '../models/recommendation.dart';
import '../services/analytics_service.dart';
import '../services/recommendation_service.dart';
import '../utils/browser_navigation.dart';
import '../utils/creator_fandom_ordering.dart';
import '../design_system/cf_design_system.dart';

class CreatorListView extends StatefulWidget {
  final List<Creator> creators;
  final String searchQuery;
  final Function(Creator) onCreatorSelected;
  final Function(Creator)? onRecommendationSelected;
  final ScrollController? scrollController;
  final VoidCallback onShouldHideListScreen;
  final VoidCallback? onClearSearch;
  final Function(String)? onSearchQueryChanged;
  final bool showFandomSuggestions;
  final ScrollPhysics? scrollPhysics;
  final double bottomPadding;
  final bool homeVisible;

  const CreatorListView({
    super.key,
    required this.creators,
    required this.searchQuery,
    required this.onCreatorSelected,
    this.onRecommendationSelected,
    required this.onShouldHideListScreen,
    this.scrollController,
    this.onClearSearch,
    this.onSearchQueryChanged,
    this.showFandomSuggestions = true,
    this.scrollPhysics,
    this.bottomPadding = 0,
    this.homeVisible = true,
  });

  @override
  State<CreatorListView> createState() => _CreatorListViewState();
}

class _CreatorListViewState extends State<CreatorListView> {
  List<Creator>? _cachedFilteredCreators;
  String? _lastSearchQuery;
  String? _lastSelectedFandom;

  List<String> get _fandomSuggestions =>
      context.read<CreatorDataProvider>().fandomSuggestions(widget.searchQuery);

  List<Creator> get _filteredCreators {
    // Return cached results if search query hasn't changed
    if (_lastSearchQuery == widget.searchQuery &&
        _cachedFilteredCreators != null) {
      return _cachedFilteredCreators!;
    }

    // Update cache
    _lastSearchQuery = widget.searchQuery;

    if (widget.searchQuery.isEmpty) {
      _cachedFilteredCreators = widget.creators;
      return _cachedFilteredCreators!;
    }

    _cachedFilteredCreators =
        context.read<CreatorDataProvider>().searchCreators(widget.searchQuery);

    return _cachedFilteredCreators!;
  }

  @override
  void didUpdateWidget(CreatorListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Clear selected fandom when search query changes (meaning user manually typed)
    // Only clear if the new query doesn't match the last selected fandom
    if (oldWidget.searchQuery != widget.searchQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = widget.scrollController;
        if (mounted && controller != null && controller.hasClients) {
          controller.jumpTo(0);
        }
      });
      if (widget.searchQuery != _lastSelectedFandom) {
        _lastSelectedFandom = null;
      }
    }

    // If creators list has changed, recompute fandom counts and clear cache
    if (oldWidget.creators != widget.creators) {
      _cachedFilteredCreators = null;
      _lastSearchQuery = null;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    context.read<RecommendationService>().setHomeVisible(
          widget.homeVisible &&
              widget.searchQuery.isEmpty &&
              !context.read<CreatorDataProvider>().isCreatorCustomListMode,
        );
    return widget.searchQuery.isNotEmpty
        ? _buildSearchResults(context)
        : _buildMainView(context, widget.onShouldHideListScreen);
  }

  Widget _buildSearchResults(BuildContext context) {
    final theme = Theme.of(context);
    final favoriteIds = context.select(
      (FavoritesService service) =>
          service.favorites.map((creator) => creator.id).toSet(),
    );
    final filteredCreators = [
      ..._filteredCreators.where((creator) => favoriteIds.contains(creator.id)),
      ..._filteredCreators
          .where((creator) => !favoriteIds.contains(creator.id)),
    ];
    final fandomSuggestions = _fandomSuggestions;
    final matchingFandoms = context
        .read<CreatorDataProvider>()
        .matchingFandomNames(widget.searchQuery);
    final xList = _homeFandomSuggestions(favoriteIds);
    final hasFandomSuggestions = widget.showFandomSuggestions &&
        fandomSuggestions.isNotEmpty &&
        _lastSelectedFandom == null;

    // Calculate item count
    int itemCount = 0;
    if (hasFandomSuggestions) {
      itemCount += 1; // Fandom suggestions section
    }
    itemCount += 1; // Results count header
    if (filteredCreators.isEmpty) {
      itemCount += 1; // No results message
    } else {
      itemCount += _filteredCreators.length; // Creator results
    }

    return ListView.builder(
      controller: widget.scrollController,
      physics: widget.scrollPhysics,
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Fandom suggestions section (first if present)
        if (hasFandomSuggestions && index == 0) {
          return _FandomSuggestions(
            suggestions: fandomSuggestions,
            onSuggestionSelected: (fandom) {
              final fandomId =
                  context.read<CreatorDataProvider>().fandomIdForName(fandom);
              if (fandomId != null) {
                context
                    .read<RecommendationService>()
                    .recordFandomInterest(fandomId);
              }
              setState(() {
                _lastSelectedFandom = fandom;
              });
              widget.onSearchQueryChanged?.call(fandom);
            },
          );
        }

        // Adjust index if fandom suggestions were shown
        final adjustedIndex = hasFandomSuggestions ? index - 1 : index;

        if (adjustedIndex == 0) {
          // Results count header with "Show on Map" button
          return _SearchResultsHeader(
            resultCount: _filteredCreators.length,
            filteredCreators: filteredCreators,
            searchQuery: widget.searchQuery,
            onShouldHideListScreen: widget.onShouldHideListScreen,
            onClearSearch: widget.onClearSearch,
          );
        }

        if (filteredCreators.isEmpty) {
          // No results message
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off,
                      size: 64,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No results found',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Regular search result
        final creator = filteredCreators[adjustedIndex - 1];
        return CreatorTile(
          creator: creator,
          onCreatorSelected: widget.onCreatorSelected,
          fandoms: orderCreatorFandoms(
            fandoms: creator.fandomNames,
            interestOrder: matchingFandoms,
            xList: xList,
          ),
        );
      },
    );
  }

  Widget _buildMainView(
      BuildContext context, VoidCallback onShouldHideListScreen) {
    final theme = Theme.of(context);
    final isCreatorCustomListMode = context.select(
        (CreatorDataProvider creatorDataProvider) =>
            creatorDataProvider.isCreatorCustomListMode);
    final showAddAllToFavorites = context.select(
        (CreatorDataProvider creatorDataProvider) =>
            creatorDataProvider.showAddAllToFavorites);
    final shouldRefreshOnReturn = context.select(
        (CreatorDataProvider creatorDataProvider) =>
            creatorDataProvider.shouldRefreshOnReturn);
    final List<Creator> favorites = isCreatorCustomListMode
        ? []
        : context.select(
            (FavoritesService favoritesService) => favoritesService.favorites);
    final recommendationService = context.watch<RecommendationService>();
    final favoriteIds = favorites.map((creator) => creator.id).toSet();
    final recommendations = isCreatorCustomListMode
        ? const <RecommendationResult>[]
        : recommendationService.recommendationsFor(
            creators: widget.creators,
            favoriteIds: favoriteIds,
            allFandoms: context.read<CreatorDataProvider>().fandomById,
            catalogVersion:
                context.read<CreatorDataProvider>().currentDataVersion ?? 0,
          );
    final popularFandomSuggestions = _fandomSuggestions;
    final fandomSuggestions = isCreatorCustomListMode
        ? popularFandomSuggestions
        : recommendationService.homeFandomSuggestionsFor(
            creators: widget.creators,
            favoriteIds: favoriteIds,
            popularFandoms: popularFandomSuggestions,
            allFandoms: context.read<CreatorDataProvider>().fandomById,
          );
    final hasFandomSuggestions = widget.showFandomSuggestions &&
        fandomSuggestions.isNotEmpty &&
        _lastSelectedFandom == null;

    // Calculate total item count for ListView.builder
    int itemCount = 0;

    // Favorites section: header + favorites + share button (if any and storage is available)
    if (favorites.isNotEmpty) {
      itemCount += 1 + favorites.length + 1; // +1 for share button
    }

    // Fandom suggestions section
    if (hasFandomSuggestions) {
      itemCount += 1;
    }

    // Personalized recommendations: header + creators.
    if (recommendations.isNotEmpty) {
      itemCount += 1 + recommendations.length;
    }

    // All creators section: header + all creators
    itemCount += 1 + _filteredCreators.length;

    if (isCreatorCustomListMode) {
      itemCount += 1;
      if (showAddAllToFavorites) {
        itemCount += 1;
      }
    }

    return ListView.builder(
      controller: widget.scrollController,
      physics: widget.scrollPhysics,
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return _buildItemAtIndex(
            index,
            theme,
            favorites,
            recommendations,
            fandomSuggestions,
            fandomSuggestions,
            isCreatorCustomListMode,
            showAddAllToFavorites,
            shouldRefreshOnReturn,
            onShouldHideListScreen);
      },
    );
  }

  Widget _buildItemAtIndex(
    int index,
    ThemeData theme,
    List<Creator> favorites,
    List<RecommendationResult> recommendations,
    List<String> fandomSuggestions,
    List<String> xList,
    bool isCreatorCustomListMode,
    bool showAddAllToFavorites,
    bool shouldRefreshOnReturn,
    VoidCallback onShouldHideListScreen,
  ) {
    final hasFandomSuggestions = widget.showFandomSuggestions &&
        fandomSuggestions.isNotEmpty &&
        _lastSelectedFandom == null;
    int currentIndex = 0;

    // Fandom suggestions sit directly below the search controls.
    if (hasFandomSuggestions) {
      if (index == currentIndex) {
        return _FandomSuggestions(
          suggestions: fandomSuggestions,
          onSuggestionSelected: (fandom) {
            final fandomId =
                context.read<CreatorDataProvider>().fandomIdForName(fandom);
            if (fandomId != null) {
              context
                  .read<RecommendationService>()
                  .recordFandomInterest(fandomId);
            }
            setState(() {
              _lastSelectedFandom = fandom;
            });
            widget.onSearchQueryChanged?.call(fandom);
          },
        );
      }
      currentIndex++;
    }

    // Favorites stay above personalized recommendations.
    if (favorites.isNotEmpty) {
      if (index == currentIndex) {
        return _FavoritesSectionHeader(
            onShouldHideListScreen: onShouldHideListScreen);
      }
      currentIndex++;

      final favoriteIndex = index - currentIndex;
      if (favoriteIndex >= 0 && favoriteIndex < favorites.length) {
        return CreatorTile(
          creator: favorites[favoriteIndex],
          onCreatorSelected: widget.onCreatorSelected,
          fandoms: orderCreatorFandoms(
            fandoms: favorites[favoriteIndex].fandomNames,
            xList: xList,
            originalFirst: true,
          ),
        );
      }
      currentIndex += favorites.length;

      if (index == currentIndex) {
        return const _ShareFavorites();
      }
      currentIndex++;
    }

    if (isCreatorCustomListMode) {
      if (index == currentIndex) {
        return _SeeAllCreatorsButton(
            onShouldHideListScreen: onShouldHideListScreen);
      }
      currentIndex++;
    } else if (recommendations.isNotEmpty) {
      if (index == currentIndex) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Creators you may like',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              letterSpacing: 0.5,
            ),
          ),
        );
      }
      currentIndex++;

      final recommendationIndex = index - currentIndex;
      if (recommendationIndex >= 0 &&
          recommendationIndex < recommendations.length) {
        final recommendation = recommendations[recommendationIndex];
        final creator = recommendation.creator;
        final onSelected =
            widget.onRecommendationSelected ?? widget.onCreatorSelected;
        return CreatorTile(
          creator: creator,
          onCreatorSelected: onSelected,
          fandoms: orderCreatorFandoms(
            fandoms: creator.fandomNames,
            interestOrder: recommendation.matchingFandoms,
            xList: xList,
          ),
        );
      }
      currentIndex += recommendations.length;
    }

    // All creators section
    if (index == currentIndex) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          isCreatorCustomListMode
              ? 'Custom Creators List'
              : 'All Comipara 7 Creators',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    currentIndex++;

    if (isCreatorCustomListMode && showAddAllToFavorites) {
      if (index == currentIndex) {
        return _AddAllToFavoritesButton(filteredCreators: _filteredCreators);
      }
      currentIndex++;
    }

    // All creators items
    final creatorIndex = index - currentIndex;
    if (creatorIndex >= 0 && creatorIndex < _filteredCreators.length) {
      return CreatorTile(
        creator: _filteredCreators[creatorIndex],
        onCreatorSelected: widget.onCreatorSelected,
        fandoms: orderCreatorFandoms(
          fandoms: _filteredCreators[creatorIndex].fandomNames,
          xList: xList,
          originalFirst: true,
        ),
      );
    }

    currentIndex += _filteredCreators.length;

    return const SizedBox.shrink();
  }

  List<String> _homeFandomSuggestions(Set<int> favoriteIds) {
    final data = context.read<CreatorDataProvider>();
    if (data.isCreatorCustomListMode) return data.popularSearches;
    return context.read<RecommendationService>().homeFandomSuggestionsFor(
          creators: widget.creators,
          favoriteIds: favoriteIds,
          popularFandoms: data.popularSearches,
          allFandoms: data.fandomById,
        );
  }
}

void _copyBoothCodeList(BuildContext context) {
  final provider = context.read<FavoritesService>();
  final boothList = provider.getBoothCodeList();
  Clipboard.setData(ClipboardData(text: boothList));
  umami.trackEvent(
    name: 'copy_booth_codes_tapped',
    data: {'count': provider.favorites.length.toString()},
  );
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Favorites booth codes copied!'),
      duration: Duration(seconds: 2),
    ),
  );
}

void _shareFavorites(BuildContext context, {required String source}) {
  final provider = context.read<FavoritesService>();
  final url = provider.getShareableUrl();
  umami.trackEvent(
    name: 'share_favorites_tapped',
    data: {'count': provider.favorites.length.toString(), 'source': source},
  );
  Clipboard.setData(ClipboardData(text: url));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Shareable Favorites URL copied!'),
      duration: Duration(seconds: 2),
    ),
  );
}

class _SeeAllCreatorsButton extends StatelessWidget {
  final VoidCallback onShouldHideListScreen;
  const _SeeAllCreatorsButton({
    required this.onShouldHideListScreen,
  });

  @override
  Widget build(BuildContext context) {
    return CfPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      accent: context.cf.pink,
      child: Column(
        spacing: 16,
        children: [
          const CfKicker('Curated route'),
          const Text(
            "You're viewing a curated creator list. Only the creators selected by the list owner are shown on the map.",
            textAlign: TextAlign.center,
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: const Icon(Icons.arrow_back, size: 19),
            label: const Text(
              'Return to Full Creator List',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                letterSpacing: 0.1,
              ),
            ),
            onPressed: () {
              umami.trackEvent(name: 'return_to_full_list_tapped');
              if (kIsWeb &&
                  context.read<CreatorDataProvider>().shouldRefreshOnReturn) {
                browserAssign('/');
              } else {
                context.read<CreatorDataProvider>().clearCreatorCustomList();
                onShouldHideListScreen();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AddAllToFavoritesButton extends StatelessWidget {
  const _AddAllToFavoritesButton({
    required List<Creator> filteredCreators,
  }) : _filteredCreators = filteredCreators;

  final List<Creator> _filteredCreators;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CfActionButton(
        icon: Icons.add,
        label: 'Add All to Favorites',
        color: context.cf.pink,
        onPressed: () {
          final favoritesService = context.read<FavoritesService>();
          final beforeCount = favoritesService.favoriteCount;
          for (final creator in _filteredCreators) {
            if (creator.id == -1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Favorite feature is currently unavailable. We\'ll add this back as soon as we can!',
                      style: TextStyle(color: Colors.white)),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }
            favoritesService.addFavorite(creator.id);
          }
          final afterCount = favoritesService.favoriteCount;
          final addedCount = afterCount - beforeCount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(addedCount == 0
                  ? 'All creators in the list are already in your favorites.'
                  : 'Added $addedCount creator${addedCount == 1 ? '' : 's'} to favorites.'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}

class _ShareFavorites extends StatelessWidget {
  const _ShareFavorites();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: CfActionButton(
        icon: Icons.share,
        label: 'Share Favorites',
        color: context.cf.cyan,
        onPressed: () => _shareFavorites(
          context,
          source: 'main_button',
        ),
        onLongPress: () => _copyBoothCodeList(context),
      ),
    );
  }
}

class _SearchResultsHeader extends StatelessWidget {
  final int resultCount;
  final List<Creator> filteredCreators;
  final String searchQuery;
  final VoidCallback onShouldHideListScreen;
  final VoidCallback? onClearSearch;

  const _SearchResultsHeader({
    required this.resultCount,
    required this.filteredCreators,
    required this.searchQuery,
    required this.onShouldHideListScreen,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$resultCount result${resultCount == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (filteredCreators.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                final creatorProvider = context.read<CreatorDataProvider>();
                final searchResultIds =
                    filteredCreators.map((c) => c.id).toList();
                umami.trackEvent(
                  name: 'show_on_map_tapped',
                  data: {
                    'source': 'search_results',
                    'count': searchResultIds.length.toString(),
                    'search_query': searchQuery,
                  },
                );
                if (searchResultIds.contains(-1)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          '"Show on Map" feature is currently unavailable. We\'ll add this back as soon as we can!',
                          style: TextStyle(color: Colors.white)),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
                creatorProvider.setCreatorCustomList(searchResultIds,
                    showAddAllToFavorites: true, shouldRefreshOnReturn: false);
                onClearSearch?.call();
                onShouldHideListScreen();
              },
              icon: Icon(
                Icons.map,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              label: Text(
                'Show on Map',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _FandomSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final Function(String)? onSuggestionSelected;

  const _FandomSuggestions({
    required this.suggestions,
    this.onSuggestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (suggestions.isEmpty || onSuggestionSelected == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: suggestions.map((fandom) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CfTag(
                label: fandom,
                color: context.cf.cyan.withValues(alpha: 0.22),
                onTap: () {
                  final fandomId = context
                      .read<CreatorDataProvider>()
                      .fandomIdForName(fandom);
                  umami.trackEvent(
                    name: 'fandom_tapped',
                    data: {
                      'source': 'search_suggestion',
                      'fandom': fandom,
                      if (fandomId != null) 'fandom_id': fandomId.toString(),
                    },
                  );
                  onSuggestionSelected?.call(fandom);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FavoritesSectionHeader extends StatelessWidget {
  final VoidCallback onShouldHideListScreen;
  const _FavoritesSectionHeader({
    required this.onShouldHideListScreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Favorites',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              final creatorProvider = context.read<CreatorDataProvider>();
              final favorites = context.read<FavoritesService>().favorites;
              final favoriteIds = favorites.map((c) => c.id).toList();
              umami.trackEvent(
                name: 'show_on_map_tapped',
                data: {
                  'source': 'favorites',
                  'count': favoriteIds.length.toString(),
                },
              );
              creatorProvider.setCreatorCustomList(favoriteIds,
                  showAddAllToFavorites: false, shouldRefreshOnReturn: false);
              onShouldHideListScreen();
            },
            icon: Icon(
              Icons.map,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            label: Text(
              'Show on Map',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          TextButton.icon(
            onPressed: () => _shareFavorites(
              context,
              source: 'favorites_header',
            ),
            onLongPress: () => _copyBoothCodeList(context),
            icon: Icon(
              Icons.share,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            label: Text(
              'Share',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
