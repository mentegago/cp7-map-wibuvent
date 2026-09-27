import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../models/creator.dart';
import '../../services/analytics_service.dart';
import '../../services/creator_data_service.dart';
import '../../services/favorites_service.dart';
import '../../services/recommendation_service.dart';
import '../../utils/int_encoding.dart';
import '../creator_list_view.dart';
import 'mobile_sheet_detent.dart';
import '../../design_system/cf_design_system.dart';

class ExpandableSearch extends StatefulWidget {
  final List<Creator> creators;
  final void Function(
    Creator, {
    required String source,
    String searchQuery,
  }) onCreatorSelected;
  final VoidCallback? onClear;
  final Creator? selectedCreator;

  const ExpandableSearch({
    super.key,
    required this.creators,
    required this.onCreatorSelected,
    this.onClear,
    this.selectedCreator,
  });

  @override
  State<ExpandableSearch> createState() => ExpandableSearchState();
}

class ExpandableSearchState extends State<ExpandableSearch> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  ScrollController? _activeScrollController;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MobileSearchSheetDetent _detent = MobileSearchSheetDetent.collapsed;
  double _collapsedExtent = 0.18;
  double _extent = 0.18;
  double _bottomSafeArea = 0;
  double? _dragStartExtent;

  MobileSearchSheetDetent get currentDetent {
    final extent =
        _sheetController.isAttached ? _sheetController.size : _extent;
    final midpoint = (_collapsedExtent + MobileSheetDetent.expanded.extent) / 2;
    return extent < midpoint
        ? MobileSearchSheetDetent.collapsed
        : MobileSearchSheetDetent.expanded;
  }

  double _extentFor(MobileSearchSheetDetent detent) =>
      detent == MobileSearchSheetDetent.collapsed
          ? _collapsedExtent
          : MobileSheetDetent.expanded.extent;

  Future<void> animateToDetent(MobileSearchSheetDetent detent) async {
    _detent = detent;
    if (!_sheetController.isAttached) return;
    await _sheetController.animateTo(
      _extentFor(detent),
      duration: mobileSheetAnimationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void jumpToDetent(MobileSearchSheetDetent detent) {
    _detent = detent;
    _extent = _extentFor(detent);
    if (_sheetController.isAttached) {
      _sheetController.jumpTo(_extentFor(detent));
    }
  }

  void resizeBehindDetail() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      MobileSheetDetent.partiallyExpanded.extent,
      duration: mobileSheetAnimationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void performSearch(String query) {
    setState(() {
      _searchController.text = query;
    });
    _performSearch(query);
    animateToDetent(MobileSearchSheetDetent.expanded);
  }

  void expandIfSearching() {
    if (_searchController.text.isNotEmpty) {
      animateToDetent(MobileSearchSheetDetent.expanded);
    }
  }

  @override
  void initState() {
    super.initState();

    _sheetController.addListener(_handleExtentChanged);
    _focusNode.addListener(() {
      if (mounted &&
          _focusNode.hasFocus &&
          currentDetent != MobileSearchSheetDetent.expanded) {
        umami.trackEvent(name: 'search_bar_opened');
        animateToDetent(MobileSearchSheetDetent.expanded);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mediaQuery = MediaQuery.of(context);
    // viewPadding is the persistent system inset and does not fluctuate with
    // the keyboard. Flutter Web can report zero on iOS Safari despite the home
    // indicator, so only that platform receives a small gesture-area fallback.
    final reportedBottomSafeArea = mediaQuery.viewPadding.bottom;
    final needsIosGestureFallback =
        kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    _bottomSafeArea = MobileSearchSheetLayout.effectiveBottomSafeArea(
      reportedBottomSafeArea,
      useGestureNavigationFallback: needsIosGestureFallback,
    );
    final nextCollapsedExtent = MobileSearchSheetLayout.collapsedExtent(
      availableHeight: mediaQuery.size.height,
      bottomSafeArea: _bottomSafeArea,
    );
    final wasCollapsed = currentDetent == MobileSearchSheetDetent.collapsed;
    if ((_collapsedExtent - nextCollapsedExtent).abs() < 0.001) return;

    _collapsedExtent = nextCollapsedExtent;
    if (!_sheetController.isAttached) {
      _extent = nextCollapsedExtent;
    } else if (wasCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheetController.isAttached) {
          jumpToDetent(MobileSearchSheetDetent.collapsed);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _sheetController
      ..removeListener(_handleExtentChanged)
      ..dispose();
    super.dispose();
  }

  void _handleExtentChanged() {
    if (!mounted || !_sheetController.isAttached) return;
    final extent = _sheetController.size;
    final detent = currentDetent;
    if ((_extent - extent).abs() > 0.001 || _detent != detent) {
      setState(() {
        _extent = extent;
        _detent = detent;
      });
    }
  }

  void _performSearch(String query) {
    if (_activeScrollController?.hasClients ?? false) {
      _activeScrollController!.jumpTo(0);
    }
  }

  void _collapse() {
    _focusNode.unfocus();
    animateToDetent(MobileSearchSheetDetent.collapsed);
  }

  void _handleCreatorTap(Creator creator) {
    _focusNode.unfocus();
    widget.onCreatorSelected(
      creator,
      source: 'list',
      searchQuery: _searchController.text,
    );
  }

  void _handleRecommendationTap(Creator creator) {
    _focusNode.unfocus();
    widget.onCreatorSelected(creator, source: 'recommendation');
  }

  void _handleClear() {
    umami.trackEvent(
      name: 'search_bar_clear_tapped',
      data: {
        'search_query': _searchController.text,
        'creator_id': widget.selectedCreator?.id.toString(),
        'creator_name': widget.selectedCreator?.name,
      },
    );
    setState(() {
      _searchController.clear();
    });
    _collapse();
    widget.onClear?.call();
  }

  void _handleSearchSubmitted(String text) {
    // Router function - delegates to specific handlers based on URL pattern
    if (text.contains('?list=')) {
      _handleListUrl(text);
    } else if (text.contains('?creator_id=')) {
      _handleCreatorIdUrl(text);
    } else if (text.contains('?creator=')) {
      _handleCreatorUrl(text);
    } else if (text.contains('?custom_list=')) {
      _handleCustomListUrl(text);
    }
  }

  void _handleListUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the list query parameter
      final listParam = uri.queryParameters['list'];
      if (listParam == null || listParam.isEmpty) {
        return; // No list parameter, fail silently
      }

      // Decode the compressed list
      final idList = IntEncoding.stringCodeToInts(listParam);
      if (idList.isEmpty) {
        return; // Empty or invalid list, fail silently
      }

      // Set creator custom list with specified flags
      final creatorProvider = context.read<CreatorDataProvider>();
      creatorProvider.setCreatorCustomList(
        idList,
        showAddAllToFavorites: true,
        shouldRefreshOnReturn: false,
      );

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCreatorIdUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the creator_id query parameter
      final creatorIdParam = uri.queryParameters['creator_id'];
      if (creatorIdParam == null || creatorIdParam.isEmpty) {
        return; // No creator_id parameter, fail silently
      }

      // Parse creator ID
      final creatorId = int.tryParse(creatorIdParam);
      if (creatorId == null) {
        return; // Invalid creator ID, fail silently
      }

      // Get creator by ID
      final creatorProvider = context.read<CreatorDataProvider>();
      final creator = creatorProvider.getCreatorById(creatorId);
      if (creator == null) {
        return; // Creator not found, fail silently
      }

      // Select the creator
      widget.onCreatorSelected(creator, source: 'deeplink');

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCreatorUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the creator query parameter
      final creatorParam = uri.queryParameters['creator'];
      if (creatorParam == null || creatorParam.isEmpty) {
        return; // No creator parameter, fail silently
      }

      // Decode and normalize name (replace + with space, trim)
      final searchName = Uri.decodeComponent(creatorParam.replaceAll('+', ' '))
          .trim()
          .toLowerCase();
      if (searchName.isEmpty) {
        return; // Empty search name, fail silently
      }

      // Get all creators from provider
      final creatorProvider = context.read<CreatorDataProvider>();
      final creators = creatorProvider.creators;
      if (creators == null || creators.isEmpty) {
        return; // No creators available, fail silently
      }

      // Find creator by name (case-insensitive, partial match)
      Creator? creator;
      try {
        creator = creators.firstWhere(
          (c) => c.name.toLowerCase().contains(searchName),
          orElse: () => creators.firstWhere(
            (c) => c.name.toLowerCase() == searchName,
            orElse: () =>
                creators.first, // fallback, won't be used if null check below
          ),
        );

        // Only select if we found a match
        if (!creator.name.toLowerCase().contains(searchName)) {
          return; // No match found, fail silently
        }
      } catch (e) {
        return; // No match found, fail silently
      }

      // Select the creator
      widget.onCreatorSelected(creator, source: 'deeplink');

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCustomListUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the custom_list query parameter
      final customListParam = uri.queryParameters['custom_list'];
      if (customListParam == null || customListParam.isEmpty) {
        return; // No custom_list parameter, fail silently
      }

      // Parse comma-separated creator IDs
      final idStrings = customListParam.split(',');
      final idList = idStrings
          .map((idStr) => int.tryParse(idStr.trim()))
          .where((id) => id != null)
          .cast<int>()
          .toList();

      if (idList.isEmpty) {
        return; // Empty or invalid list, fail silently
      }

      // Set creator custom list with specified flags
      final creatorProvider = context.read<CreatorDataProvider>();
      creatorProvider.setCreatorCustomList(
        idList,
        showAddAllToFavorites: true,
        shouldRefreshOnReturn: false,
      );

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final contentOpacity = ((_extent - _collapsedExtent) /
            (MobileSheetDetent.expanded.extent - _collapsedExtent))
        .clamp(0.0, 1.0);
    final collapsedHeaderBottomInset =
        MobileSearchSheetLayout.collapsedHeaderBottomInset(
      bottomSafeArea: _bottomSafeArea,
      expansionProgress: contentOpacity,
    );

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _collapsedExtent,
      minChildSize: _collapsedExtent,
      maxChildSize: MobileSheetDetent.expanded.extent,
      snap: true,
      snapAnimationDuration: mobileSheetAnimationDuration,
      shouldCloseOnMinExtent: false,
      builder: (context, sheetScrollController) {
        _activeScrollController = sheetScrollController;
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              decoration: BoxDecoration(
                color: context.cf.paperRaised,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: context.cf.ink, width: 1.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildSheetHeader(
                    context,
                    isDark: isDark,
                    bottomInset: collapsedHeaderBottomInset,
                    availableHeight: constraints.maxHeight /
                        (_sheetController.isAttached
                            ? _sheetController.size
                            : _extent),
                  ),
                  Expanded(
                    child: IgnorePointer(
                      ignoring: contentOpacity < 0.95,
                      child: Opacity(
                        opacity: contentOpacity,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _searchController,
                          builder: (context, value, _) {
                            return CreatorListView(
                              creators: widget.creators,
                              searchQuery: value.text,
                              onCreatorSelected: _handleCreatorTap,
                              onRecommendationSelected:
                                  _handleRecommendationTap,
                              scrollController: sheetScrollController,
                              onShouldHideListScreen: _collapse,
                              onClearSearch: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                              onSearchQueryChanged: (query) {
                                _searchController.text = query;
                                _performSearch(query);
                              },
                              showFandomSuggestions: false,
                              scrollPhysics: const ClampingScrollPhysics(),
                              bottomPadding: _bottomSafeArea,
                              homeVisible: widget.selectedCreator == null,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetHeader(
    BuildContext context, {
    required bool isDark,
    required double availableHeight,
    required double bottomInset,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _dragStartExtent =
            _sheetController.isAttached ? _sheetController.size : _extent;
      },
      onVerticalDragUpdate: (details) {
        if (!_sheetController.isAttached || _dragStartExtent == null) return;
        final next =
            (_dragStartExtent! - details.primaryDelta! / availableHeight)
                .clamp(_collapsedExtent, MobileSheetDetent.expanded.extent);
        _dragStartExtent = next;
        _sheetController.jumpTo(next);
      },
      onVerticalDragEnd: (details) {
        if (!_sheetController.isAttached) return;
        final velocity = details.primaryVelocity ?? 0;
        final current = _sheetController.size;
        MobileSearchSheetDetent target;
        if (velocity < -500) {
          target = MobileSearchSheetDetent.expanded;
        } else if (velocity > 500) {
          target = MobileSearchSheetDetent.collapsed;
        } else {
          final midpoint =
              (_collapsedExtent + MobileSheetDetent.expanded.extent) / 2;
          target = current < midpoint
              ? MobileSearchSheetDetent.collapsed
              : MobileSearchSheetDetent.expanded;
        }
        _dragStartExtent = null;
        animateToDetent(target);
      },
      child: Column(
        children: [
          const Center(child: CfSheetGrip()),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: context.cf.paper,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(5),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: context.cf.ink, width: 1.5),
              boxShadow: [
                BoxShadow(color: context.cf.cyan, offset: const Offset(3, 3)),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(Icons.search, color: context.cf.pink),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Search name, booth, or fandom...',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: _performSearch,
                    onSubmitted: _handleSearchSubmitted,
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isNotEmpty || widget.onClear != null) {
                      return IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(
                          Icons.close,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                          size: 20,
                        ),
                        onPressed: _handleClear,
                      );
                    }
                    return const SizedBox(width: 8);
                  },
                ),
              ],
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              final suggestions = _headerFandomSuggestions(context, value.text);
              if (suggestions.isEmpty) return const SizedBox(height: 36);
              return SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final fandom = suggestions[index];
                    return Center(
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
                              if (fandomId != null)
                                'fandom_id': fandomId.toString(),
                            },
                          );
                          if (fandomId != null) {
                            context
                                .read<RecommendationService>()
                                .recordFandomInterest(fandomId);
                          }
                          _focusNode.unfocus();
                          performSearch(fandom);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  List<String> _headerFandomSuggestions(
    BuildContext context,
    String searchQuery,
  ) {
    final data = context.read<CreatorDataProvider>();
    if (searchQuery.trim().isNotEmpty) {
      return data.fandomSuggestions(searchQuery);
    }
    if (data.isCreatorCustomListMode) {
      return data.popularSearches;
    }
    final favoriteIds = context
        .watch<FavoritesService>()
        .favorites
        .map((creator) => creator.id)
        .toSet();
    return context.watch<RecommendationService>().homeFandomSuggestionsFor(
          creators: widget.creators,
          favoriteIds: favoriteIds,
          popularFandoms: data.popularSearches,
          allFandoms: data.fandomById,
        );
  }
}
