import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/app/router/route_handle.dart';
import 'package:defiwawa/app/router/route_paths.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/lib/view_time.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/discovery/presentation/sheets/discovery_sheets.dart';
import 'package:defiwawa/features/discovery/presentation/widgets/discovery_widgets.dart';
import 'package:defiwawa/features/discovery/providers/discovery_provider.dart';
import 'package:defiwawa/features/discovery/services/discovery_services.dart';
import 'package:defiwawa/features/navigation/presentation/navigation_ui.dart';
import 'package:defiwawa/features/navigation/providers/navigation_provider.dart';
import 'package:defiwawa/features/map/lib/map_camera.dart';
import 'package:defiwawa/features/map/presentation/widgets/map_view.dart';
import 'package:defiwawa/features/map/presentation/widgets/map_widgets.dart';

const _scrim = Color(0xFF17231D);
const _cornerScrim = Color(0x7317231D);

/// App shell: the map stays mounted; the active route renders into the bottom sheet; the find button is pinned.
class MapPage extends HookConsumerWidget {
  const MapPage({super.key, required this.path, required this.child});

  final String path;

  /// The route's panel (a navigator inside the sheet).
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handle = RouteHandle.of(path);
    final floating = handle.floating;
    final navigating = handle.navigation;
    final padding = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;

    final mapFailed = useState(false);
    final mapKey = useState(0);
    // One pop-up next to the round controls at a time: the time picker or the AED filters.
    final filtersOpen = useState(false);
    // Phones: layers, time and filters fold behind the "more" button.
    final moreOpen = useState(false);
    // Map bottom covered by the sheet (as reported for its route) or the pinned find bar.
    final sheetReport = useState<(String, double)?>(null);
    final dockHeight = useState(0.0);

    useEffect(() {
      Future.microtask(ref.read(aedsProvider.notifier).load);
      return null;
    }, const []);

    final discovery = ref.read(discoveryProvider.notifier);
    final aeds = ref.read(aedsProvider.notifier);
    final picking = ref.watch(discoveryProvider.select((s) => s.picking));
    // The address search stays at the top of every screen, as in Google Maps, except while navigating or picking.
    final searchShown = !navigating && !picking;
    final issue = ref.watch(discoveryProvider.select((s) => s.issue));
    final locating = ref.watch(discoveryProvider.select((s) => s.locating));
    final searching = ref.watch(discoveryProvider.select((s) => s.search is SearchSearching));
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final live = ref.watch(aedsProvider.select((s) => s.live));
    // One time for the whole map; a preview stays visible in its banner after the picker closes.
    final timeOpen = ref.watch(aedsProvider.select((s) => s.pickerOpen));
    final filters = ref.watch(mapFiltersProvider);
    final show = showResult(context);

    void toggleTime() {
      if (!timeOpen) filtersOpen.value = false;
      aeds.setTimePickerOpen(!timeOpen);
    }

    void toggleFilters() {
      if (!filtersOpen.value) aeds.setTimePickerOpen(false);
      filtersOpen.value = !filtersOpen.value;
    }

    void onClose() {
      if (handle.close == RouteClose.selection) discovery.clearSelection();
      context.go(RoutePaths.map);
    }

    Future<void> onFind() async {
      final result = await discovery.findNearest();
      if (!context.mounted) return;
      if (result?.selected != null) return show(result);
      // "Nothing found", failures and location problems are explained on the start screen; a cancel stays put.
      final state = ref.read(discoveryProvider);
      if (state.search is! SearchIdle || state.issue != null) context.go(RoutePaths.map);
    }

    Future<void> onLocate() async {
      if (navigating) return ref.read(navigationProvider.notifier).showMyPosition();
      final origin = await discovery.locate();
      if (origin != null) mapCamera.focus(origin);
    }

    return PopScope(
      canPop: path == RoutePaths.map,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(handle.parent);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewportHeight = constraints.maxHeight;
              // The expanded sheet stops below the header, or below the taller direction banner.
              final maxSheet = viewportHeight - padding.top - (navigating ? 160 : 80);
              final report = sheetReport.value;
              final sheetCover = floating
                  ? 0.0
                  : report != null && report.$1 == path
                  ? report.$2
                  : DefiSheet.heightFor(handle.sheet, maxSheet);
              final cover = max(sheetCover, dockHeight.value);
              // Camera moves for the new route use the final inset.
              mapCamera.bottomInset = cover;
              final showControls = cover < viewportHeight * 0.7;
              final aboveCover = cover + AppSpacing.s48;
              // Folds again whenever the column goes away, like the web's remounted controls.
              if (moreOpen.value && (!showControls || navigating)) Future.microtask(() => moreOpen.value = false);
              final locateButton = LocateButton(onPressed: locating ? null : onLocate);

              return Stack(
                fit: StackFit.expand,
                children: [
                  MapView(
                    key: ValueKey(mapKey.value),
                    selectedId: handle.selectedId,
                    navigating: navigating,
                    showCoverage: path == RoutePaths.coverage,
                    showPlacement: path == RoutePaths.placement,
                    bottomInset: cover,
                    onLoadError: () => mapFailed.value = true,
                    onSelectAed: (id) => context.go(RoutePaths.aedPath(id)),
                  ),
                  // Bottom-right corner scrim under the round controls and the find bar, moving with the cover.
                  // Its lower edge carries on down to the screen bottom, under the sheet, so the map never shows
                  // light under the sheet's rounded corners or while the scrim catches up with a dragged sheet.
                  if (!navigating)
                    AnimatedPositioned(
                      duration: AppDurations.panel,
                      curve: Curves.easeOut,
                      right: 0,
                      bottom: 0,
                      height: cover + 160,
                      width: width * 0.7,
                      child: const IgnorePointer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 160,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment.bottomRight,
                                    radius: 1,
                                    colors: [_cornerScrim, Color(0x0017231D)],
                                    transform: _StretchToWidth(),
                                  ),
                                ),
                              ),
                            ),
                            // The radial gradient's bottom row, repeated.
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerRight,
                                    end: Alignment.centerLeft,
                                    colors: [_cornerScrim, Color(0x0017231D)],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: padding.top + (navigating ? 160 : 76),
                    left: AppSpacing.s16,
                    right: AppSpacing.s16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.s8,
                      children: [
                        // No instruction banner while picking; only a tap outside Warsaw is explained.
                        if (picking && issue == LocationIssue.outsidePick)
                          PickOriginBanner(outside: true, onCancel: discovery.stopPicking),
                        if (OriginIssueNotice.shows(issue) && !picking && !handle.showsLocationIssue)
                          _floating(
                            OriginIssueNotice(issue: issue!, onPick: discovery.startPicking, onRetry: onLocate),
                          ),
                        if (!live)
                          _floating(
                            DefiNotice(
                              tone: Tone.warning,
                              title: 'Podgląd: ${formatWarsawTime(now)}',
                              actions: [DefiButton(label: 'Wróć do teraz', onPressed: aeds.resetViewTime)],
                              child: const Text('Mapa pokazuje dostępność o tej porze, nie teraz.'),
                            ),
                          ),
                        if (mapFailed.value)
                          _floating(
                            DefiNotice(
                              tone: Tone.danger,
                              title: 'Nie udało się wczytać mapy.',
                              actions: [
                                DefiButton(
                                  label: 'Spróbuj ponownie',
                                  onPressed: () {
                                    mapFailed.value = false;
                                    mapKey.value++;
                                  },
                                ),
                                DefiButton(
                                  icon: AppIconName.list,
                                  label: 'Lista defibrylatorów',
                                  onPressed: () => context.go(RoutePaths.aeds),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showControls)
                    _Animated(
                      right: AppSpacing.s16,
                      // Navigation: the lone locate square's face, not its 4 px larger hit area, sits 16 above the cover.
                      bottom: cover + (navigating ? AppSpacing.s12 : AppSpacing.s16),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned(left: -48, right: -16, top: -48, bottom: -48, child: _ControlsScrim()),
                          // Navigation: no layers, time or filters.
                          if (navigating)
                            locateButton
                          else
                            MapControls(
                              moreOpen: moreOpen.value,
                              coverageShown: path == RoutePaths.coverage,
                              placementShown: path == RoutePaths.placement,
                              timeOpen: timeOpen,
                              filtersOpen: filtersOpen.value,
                              onToggleMore: () => moreOpen.value = !moreOpen.value,
                              onToggleCoverage: () =>
                                  context.go(path == RoutePaths.coverage ? RoutePaths.map : RoutePaths.coverage),
                              onTogglePlacement: () =>
                                  context.go(path == RoutePaths.placement ? RoutePaths.map : RoutePaths.placement),
                              onToggleTime: toggleTime,
                              onToggleFilters: toggleFilters,
                              locate: locateButton,
                            ),
                        ],
                      ),
                    ),
                  if (filtersOpen.value && moreOpen.value && showControls && !navigating)
                    _Animated(
                      right: AppSpacing.s16 + 56 + AppSpacing.s8,
                      // Level with the bottom of the filter tile, right above the "more" button.
                      bottom: cover + AppSpacing.s16 + 48 + AppSpacing.s8,
                      child: FilterMenu(
                        filters: filters,
                        onToggle: ref.read(mapFiltersProvider.notifier).toggle,
                        onClose: () => filtersOpen.value = false,
                      ),
                    ),
                  if (timeOpen && showControls && !navigating)
                    _Animated(
                      left: AppSpacing.s16,
                      right: AppSpacing.s16 + 56 + AppSpacing.s8,
                      bottom: aboveCover,
                      child: Align(
                        alignment: Alignment.centerRight,
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: SizedBox(
                            width: double.infinity,
                            child: TimeBar(
                              at: now,
                              live: live,
                              onChange: (day, minutes) =>
                                  aeds.setViewTime(nextWarsawWeekday(day, minutes, DateTime.now())),
                              onNow: aeds.resetViewTime,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Pinned find bar on every screen: a white bar on the bottom edge. An open sheet covers it.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _MeasureHeight(
                      onChange: (h) => dockHeight.value = h,
                      child: IgnorePointer(
                        ignoring: !floating,
                        child: ExcludeSemantics(
                          excluding: !floating,
                          child: Container(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.s16,
                              AppSpacing.s12,
                              AppSpacing.s16,
                              AppSpacing.s12 + padding.bottom,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.surface,
                              border: Border(top: BorderSide(color: AppColors.border)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Start screen status (search outcome, location problems); empty most of the time.
                                if (floating)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxHeight: viewportHeight / 2),
                                    child: const SingleChildScrollView(child: StartPanel()),
                                  ),
                                if (!navigating)
                                  FindButton(searching: searching, onFind: onFind, onCancel: discovery.cancelSearch),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (floating)
                    Positioned.fill(child: Offstage(child: child))
                  else
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DefiSheet(
                        key: ValueKey(path),
                        maxHeight: maxSheet,
                        initialSnap: handle.sheet,
                        onHeightChanged: (h) => sheetReport.value = (path, h),
                        onClose: handle.close != null ? onClose : null,
                        child: child,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Stack(
                      children: [
                        // Dark scrim keeps the white header readable on a light map; it never catches taps.
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x7317231D), Color(0x0017231D)],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.s16,
                            padding.top + AppSpacing.s12,
                            AppSpacing.s16,
                            AppSpacing.s32,
                          ),
                          // The direction banner takes the header's place at the top of the screen; the search's D
                          // is the logo, so the logo pill shows only while picking a point off the start screen.
                          child: navigating
                              ? const NavigationBanner()
                              : searchShown
                              ? AddressSearch(
                                  onSearch: ref.read(geocodingServiceProvider).searchAddresses,
                                  onChoose: (hit) => discovery.findFromAddress(hit.location).then(show),
                                  onPickOnMap: () => discovery.startPicking((p) => discovery.findFrom(p).then(show)),
                                )
                              : floating
                              ? const SizedBox.shrink()
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: AppHeader(onHome: () => context.go(RoutePaths.map)),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Cards over the map get the floating shadow (web .overlay > *).
  static Widget _floating(Widget child) => DecoratedBox(
    decoration: const BoxDecoration(borderRadius: AppRadius.control, boxShadow: AppShadows.floating),
    child: child,
  );
}

/// Positioned that follows the sheet with the panel transition.
class _Animated extends StatelessWidget {
  const _Animated({this.left, this.right, required this.bottom, required this.child});

  final double? left;
  final double? right;
  final double bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPositioned(
    duration: AppDurations.panel,
    curve: Curves.easeOut,
    left: left,
    right: right,
    bottom: bottom,
    child: child,
  );
}

/// Scrim behind the control column: darker towards the screen edge, fading out above and below.
class _ControlsScrim extends StatelessWidget {
  const _ControlsScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, 48 / rect.height, 1 - 48 / rect.height, 1],
        ).createShader(rect),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [_scrim.withValues(alpha: 0.3), _scrim.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stretches a circular gradient into the CSS `farthest-side` ellipse anchored at the bottom-right corner.
class _StretchToWidth extends GradientTransform {
  const _StretchToWidth();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.right, bounds.bottom, 0)
        ..multiply(Matrix4.diagonal3Values(bounds.width / bounds.height, 1, 1))
        ..multiply(Matrix4.translationValues(-bounds.right, -bounds.bottom, 0));
}

/// Reports its child's height after layout (the find bar covers the bottom of the map).
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight renderObject) => renderObject.onChange = onChange;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onChange);

  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
  }
}
