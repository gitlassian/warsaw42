import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:defiwawa/features/coverage/presentation/sheets/coverage_panel.dart';
import 'package:defiwawa/features/discovery/presentation/sheets/discovery_sheets.dart';
import 'package:defiwawa/features/map/presentation/pages/map_page.dart';
import 'package:defiwawa/features/navigation/presentation/navigation_ui.dart';
import 'package:defiwawa/features/placement/presentation/sheets/placement_panel.dart';
import 'package:defiwawa/features/report/presentation/sheets/report_panel.dart';
import 'package:defiwawa/app/router/route_paths.dart';

/// A route's panel in the bottom sheet, swapped without a transition like the web.
GoRouterPageBuilder _sheet(Widget Function(GoRouterState state) panel) =>
    (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: DefiSheetScroll(child: panel(state)),
    );

String _id(GoRouterState state) => state.pathParameters['id']!;

/// The map page stays mounted; the active route renders into the sheet. Unknown paths go to the map.
final appRouter = GoRouter(
  onException: (_, _, router) => router.go(RoutePaths.map),
  routes: [
    ShellRoute(
      builder: (context, state, child) => MapPage(path: state.uri.path, child: child),
      routes: [
        // The start screen's status lives in the find bar, outside the sheet (MapPage).
        GoRoute(
          path: RoutePaths.map,
          pageBuilder: (_, _) => const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(path: RoutePaths.aeds, pageBuilder: _sheet((_) => const NearbyListPanel())),
        GoRoute(
          path: RoutePaths.aed,
          pageBuilder: _sheet((s) => AedDetailsPanel(id: _id(s))),
        ),
        GoRoute(
          path: RoutePaths.navigate,
          pageBuilder: _sheet((s) => NavigationPanel(id: _id(s))),
        ),
        GoRoute(
          path: RoutePaths.report,
          pageBuilder: _sheet((s) => ReportPanel(id: _id(s))),
        ),
        GoRoute(path: RoutePaths.coverage, pageBuilder: _sheet((_) => const CoveragePanel())),
        GoRoute(path: RoutePaths.placement, pageBuilder: _sheet((_) => const PlacementPanel())),
      ],
    ),
  ],
);
