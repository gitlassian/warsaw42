import 'package:go_router/go_router.dart';

import '../../features/map/presentation/pages/map_page.dart';
import 'route_paths.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: RoutePaths.map, builder: (_, _) => const MapPage()),
  ],
);
