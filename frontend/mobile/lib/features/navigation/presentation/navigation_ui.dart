import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/app/router/route_paths.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/presentation/widgets/aed_widgets.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/discovery/presentation/sheets/discovery_sheets.dart';
import 'package:defiwawa/features/discovery/providers/discovery_provider.dart';
import 'package:defiwawa/features/map/lib/map_camera.dart';
import 'package:defiwawa/features/navigation/lib/progress.dart';
import 'package:defiwawa/features/navigation/providers/navigation_provider.dart';

const _swipePx = 48.0;
const _white = Color(0xFFFFFFFF);

/// Google Maps-style direction banner: next maneuver arrow, distance to it, instruction, and the one after.
class NavigationBanner extends HookConsumerWidget {
  const NavigationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(navigationViewProvider);
    final aedId = ref.watch(navigationProvider.select((s) => s.aedId));
    final position = ref.watch(navigationProvider.select((s) => s.position));
    final aed = ref.watch(aedsProvider.select((s) => aedId == null ? null : s.byId[aedId]));
    final rerouting = ref.watch(discoveryProvider.select((s) => s.routing?.status == RoutingStatus.loading));
    final swipe = useRef(0.0);

    if (aedId == null) return const SizedBox.shrink();

    Widget card(List<Widget> main, {Widget? then}) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: AppRadius.control,
        boxShadow: AppShadows.panel,
      ),
      child: DefaultTextStyle(
        style: AppTextStyles.label.copyWith(color: _white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
              child: Row(spacing: AppSpacing.s16, children: main),
            ),
            ?then,
          ],
        ),
      ),
    );
    final instructionStyle = AppTextStyles.heading.copyWith(color: _white, height: 24 / 18);
    final distanceStyle = AppTextStyles.time.copyWith(color: _white, fontSize: 28, height: 34 / 28);
    Widget arrow(Widget child) => SizedBox.square(dimension: 48, child: Center(child: child));

    if (view == null) {
      return Semantics(
        liveRegion: true,
        child: card([
          arrow(rerouting ? const DefiSpinner() : const AppIcon(AppIconName.route, size: 40)),
          Expanded(
            child: Text(rerouting ? 'Wyznaczamy trasę…' : 'Brak trasy do tego defibrylatora.', style: instructionStyle),
          ),
        ]),
      );
    }

    if (view.arrived && aed != null) {
      return Semantics(
        liveRegion: true,
        child: card([
          arrow(const AppIcon(AppIconName.aed, size: 40)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jesteś na miejscu', style: distanceStyle),
                Text(
                  aed.entrance ?? placementLabel(aed),
                  style: instructionStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ]),
      );
    }

    final steps = view.steps;
    final index = view.index;
    final step = index < steps.length ? steps[index] : null;
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final browsable = !view.live && steps.length > 1;
    final distanceM = view.distanceM;
    final navigation = ref.read(navigationProvider.notifier);
    void go(int i) {
      if (i >= 0 && i < steps.length) navigation.previewStep(view.route, i);
    }

    Widget page(AppIconName icon, String label, bool enabled, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: AppIcon(icon, color: _white)),
          ),
        ),
      ),
    );

    // Swiping the banner sideways browses the steps, as in Google Maps.
    final banner = GestureDetector(
      onHorizontalDragStart: (_) => swipe.value = 0,
      onHorizontalDragUpdate: (d) => swipe.value += d.delta.dx,
      onHorizontalDragEnd: (_) {
        if (steps.length >= 2 && swipe.value.abs() >= _swipePx) go(index + (swipe.value < 0 ? 1 : -1));
      },
      child: Semantics(
        label: 'Wskazówki',
        container: true,
        child: card(
          [
            arrow(AppIcon(step != null ? maneuverIcon(step) : AppIconName.navigation, size: 40)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (distanceM != null) ExcludeSemantics(child: Text(formatDistance(distanceM), style: distanceStyle)),
                  // Distance changes with every GPS fix; only the instruction is announced.
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      step?.instruction ?? 'Idź wyznaczoną trasą do defibrylatora.',
                      style: instructionStyle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          then: next == null && !browsable
              ? null
              : Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s4, AppSpacing.s8, AppSpacing.s4),
                  color: AppColors.accentPressed,
                  child: Row(
                    spacing: AppSpacing.s8,
                    children: [
                      if (next != null) ...[
                        const Text('Następnie'),
                        AppIcon(maneuverIcon(next), size: 20, label: next.instruction),
                      ],
                      const Spacer(),
                      if (browsable) ...[
                        page(AppIconName.chevronLeft, 'Poprzedni krok', index > 0, () => go(index - 1)),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${index + 1}/${steps.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                        page(AppIconName.chevronRight, 'Następny krok', index < steps.length - 1, () => go(index + 1)),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s8,
      children: [
        banner,
        if (view.offRoute && position != null)
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s8, AppSpacing.s8),
              decoration: const BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: AppRadius.control,
                boxShadow: AppShadows.floating,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Zboczono z trasy', style: AppTextStyles.label.copyWith(color: AppColors.warning)),
                  ),
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: rerouting ? null : () => ref.read(discoveryProvider.notifier).rerouteFrom(position, aedId),
                      child: Opacity(
                        opacity: rerouting ? 0.6 : 1,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 40),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
                          decoration: const BoxDecoration(color: AppColors.warning, borderRadius: AppRadius.pill),
                          child: Text(
                            rerouting ? 'Wyznaczamy…' : 'Wyznacz nową trasę',
                            style: AppTextStyles.label.copyWith(color: _white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

const _trackingNotice = {
  Tracking.denied: 'Brak dostępu do lokalizacji. Przeglądaj kroki strzałkami na górze ekranu.',
  Tracking.unavailable: 'Słaby sygnał GPS. Wskazówki wrócą, gdy pozycja się odświeży.',
};

/// Turn-by-turn mode (sheet): time left, GPS state, step list, then finding and using the AED.
class NavigationPanel extends HookConsumerWidget {
  const NavigationPanel({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aed = ref.watch(aedsProvider.select((s) => s.byId[id]));
    final routing = ref.watch(discoveryProvider.select((s) => s.routing?.aedId == id ? s.routing!.status : null));
    final tracking = ref.watch(navigationProvider.select((s) => s.tracking));
    final following = ref.watch(navigationProvider.select((s) => s.following));
    final view = ref.watch(navigationViewProvider);
    final navigation = ref.read(navigationProvider.notifier);
    final discovery = ref.read(discoveryProvider.notifier);
    // Real time for the arrival estimate; the map's view time may be a preview.
    final clock = useState(DateTime.now());

    useEffect(() {
      // Provider changes wait for the end of the frame: the tree is building or being torn down here.
      Future.microtask(() => navigation.startNavigation(id));
      return () => Future.microtask(() {
        navigation.stopNavigation();
        mapCamera.exitNavigation();
      });
    }, [id]);

    useEffect(() {
      final timer = Stream.periodic(const Duration(seconds: 30)).listen((_) => clock.value = DateTime.now());
      return timer.cancel;
    }, const []);

    if (aed == null) return const DefiLoadingText('Wczytujemy dane…');

    if (view == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s16,
        children: [
          DefiText(aed.venueName, variant: TextVariant.name),
          if (routing == RoutingStatus.loading)
            const DefiLoadingText('Wyznaczamy trasę…')
          else
            DefiNotice(
              tone: routing == RoutingStatus.failed ? Tone.danger : Tone.neutral,
              title: routing == RoutingStatus.failed ? 'Nie udało się wyznaczyć trasy.' : 'Najpierw wyznacz trasę.',
              actions: [
                DefiButton(
                  variant: ButtonVariant.primary,
                  icon: AppIconName.directionsWalk,
                  label: 'Wyznacz trasę',
                  onPressed: () => discovery.routeTo(id),
                ),
              ],
            ),
          const AedUsageGuide(onCall: callEmergency),
        ],
      );
    }

    final arrived = view.arrived;
    final arrival = clock.value.add(Duration(seconds: view.remainingSeconds.round()));
    final guides = [AedFindingGuide(aed: aed), const AedUsageGuide(onCall: callEmergency)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        // Time left on the left, the end button on the right (the route has no corner close button).
        Row(
          spacing: AppSpacing.s12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefiText(
                    arrived ? 'Na miejscu' : formatDuration(view.remainingSeconds),
                    variant: TextVariant.time,
                    tone: TextTone.accent,
                  ),
                  DefiText(
                    arrived ? aed.venueName : '${formatDistance(view.remainingM)} · przybycie ${formatClock(arrival)}',
                    variant: TextVariant.meta,
                    tone: TextTone.secondary,
                  ),
                ],
              ),
            ),
            DefiButton(
              icon: AppIconName.close,
              label: 'Zakończ',
              expand: false,
              onPressed: () => context.go(RoutePaths.aedPath(id)),
            ),
          ],
        ),
        if (tracking == Tracking.off)
          DefiNotice(
            title: 'Trasa z wybranego punktu.',
            actions: [
              DefiButton(
                icon: AppIconName.myLocation,
                label: 'Prowadź z mojej lokalizacji',
                onPressed: () => navigation.navigateFromHere(id),
              ),
            ],
            child: const Text('Przeglądaj kroki strzałkami na górze ekranu albo wybierz krok z listy.'),
          ),
        if (tracking == Tracking.waiting) const DefiLoadingText('Szukamy Twojej pozycji…'),
        if (_trackingNotice[tracking] case final text?) DefiNotice(tone: Tone.warning, title: text),
        if (tracking == Tracking.on && !following)
          DefiButton(icon: AppIconName.nearMe, label: 'Wróć do mojej pozycji', onPressed: navigation.followPosition),
        if (arrived) ...guides,
        if (view.steps.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s8,
            children: [
              const DefiText('Wskazówki', variant: TextVariant.heading),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, step) in view.steps.indexed)
                    _StepRow(
                      icon: maneuverIcon(step),
                      instruction: step.instruction,
                      distance: step.distanceM > 0 ? formatDistance(step.distanceM) : null,
                      current: i == view.index,
                      onTap: () => navigation.previewStep(view.route, i),
                    ),
                ],
              ),
            ],
          ),
        if (!arrived) ...guides,
        const DefiText(
          'Trasa: Mapbox, © OpenStreetMap. Uważaj na ruch uliczny; wskazówki mogą nie uwzględniać przejść i zamkniętych bram.',
          variant: TextVariant.meta,
          tone: TextTone.muted,
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.instruction,
    required this.distance,
    required this.current,
    required this.onTap,
  });

  final AppIconName icon;
  final String instruction;
  final String? distance;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: current,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12, horizontal: AppSpacing.s8),
          decoration: current
              ? const BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.control)
              : const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.s16,
            children: [
              SizedBox.square(
                dimension: 32,
                child: Center(child: AppIcon(icon, color: AppColors.accent)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefiText(instruction),
                    if (distance != null) DefiText(distance!, variant: TextVariant.meta, tone: TextTone.secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
