import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:umami_analytics/umami_analytics.dart';
import 'screens/map_screen.dart';
import 'services/analytics_service.dart';
import 'services/favorites_service.dart';
import 'services/creator_data_service.dart';
import 'services/recommendation_service.dart';
import 'design_system/cf_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final disableRecommendations = _recommendationsDisabled(Uri.base);
  final creatorDataProvider = CreatorDataProvider()..initialize();
  final favoritesService = FavoritesService(creatorDataProvider)..initialize();
  final recommendationService = RecommendationService(
    disabled: disableRecommendations,
  )..initialize();

  runApp(CFMapApp(
    creatorDataProvider: creatorDataProvider,
    favoritesService: favoritesService,
    recommendationService: recommendationService,
  ));
}

bool _recommendationsDisabled(Uri uri) {
  final value = uri.queryParameters['disable_recommendations']?.toLowerCase();
  return value == '1' || value == 'true';
}

class CFMapApp extends StatelessWidget {
  final CreatorDataProvider creatorDataProvider;
  final FavoritesService favoritesService;
  final RecommendationService recommendationService;
  const CFMapApp({
    super.key,
    required this.creatorDataProvider,
    required this.favoritesService,
    required this.recommendationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => creatorDataProvider,
        ),
        ChangeNotifierProvider(
          create: (context) => favoritesService,
        ),
        ChangeNotifierProvider(
          create: (context) => recommendationService,
        ),
      ],
      child: MaterialApp(
        title: 'Comipara 7 Map',
        theme: buildCfTheme(Brightness.light),
        darkTheme: buildCfTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        navigatorObservers: [UmamiNavigatorObserver(analytics: umami)],
        home: const MapScreen(),
      ),
    );
  }
}
