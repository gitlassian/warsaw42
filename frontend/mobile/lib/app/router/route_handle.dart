import 'package:design_system/design_system.dart';

import 'package:defiwawa/app/router/route_paths.dart';

/// Close button in the sheet corner, back to the start screen.
enum RouteClose {
  /// The selected AED: closing also clears its route.
  selection,

  /// A map panel: coverage or where to add AEDs.
  panel,
}

/// How the map page presents a route (mirrors the web router handles).
class RouteHandle {
  const RouteHandle({
    this.sheet = SheetSnap.medium,
    this.showsLocationIssue = false,
    this.floating = false,
    this.close,
    this.navigation = false,
    this.selectedId,
    this.parent = RoutePaths.map,
  });

  /// Initial bottom-sheet height.
  final SheetSnap sheet;

  /// The panel renders location problems itself; otherwise the map overlay does.
  final bool showsLocationIssue;

  /// Start screen: no sheet; the status sits above the find button.
  final bool floating;
  final RouteClose? close;

  /// Turn-by-turn mode: the direction banner replaces the header and the find button is hidden.
  final bool navigation;

  /// The AED shown on the map as selected.
  final String? selectedId;

  /// Where the system back button goes.
  final String parent;

  static RouteHandle of(String path) => switch (Uri.parse(path).pathSegments) {
    ['aeds'] => const RouteHandle(showsLocationIssue: true),
    ['aed', final id] => RouteHandle(showsLocationIssue: true, close: RouteClose.selection, selectedId: id),
    ['aed', final id, 'navigate'] => RouteHandle(
      sheet: SheetSnap.compact,
      navigation: true,
      selectedId: id,
      parent: RoutePaths.aedPath(id),
    ),
    ['report', final id] => RouteHandle(
      sheet: SheetSnap.expanded,
      close: RouteClose.selection,
      selectedId: id,
      parent: RoutePaths.aedPath(id),
    ),
    ['coverage'] || ['placement'] => const RouteHandle(close: RouteClose.panel),
    _ => const RouteHandle(floating: true, showsLocationIssue: true),
  };
}
