import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:defiwawa/app/router/route_paths.dart';
import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/presentation/widgets/aed_widgets.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/discovery/providers/discovery_provider.dart';
import 'package:defiwawa/features/discovery/presentation/widgets/discovery_widgets.dart';

void callEmergency() => launchUrl(Uri(scheme: 'tel', path: '112'));

/// Opens the AED card of a search result.
void Function(FindResult? result) showResult(BuildContext context) {
  final router = GoRouter.of(context);
  return (result) {
    if (result?.selected case final selected?) router.go(RoutePaths.aedPath(selected.aed.id));
  };
}

/// Start screen status above the pinned find button: search outcome, location and data problems (DESIGN.md §6).
/// Empty most of the time; when it shows, it keeps 16 between itself and the button.
class StartPanel extends ConsumerWidget {
  const StartPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(discoveryProvider.select((s) => s.search));
    final issue = ref.watch(discoveryProvider.select((s) => s.issue));
    final origin = ref.watch(discoveryProvider.select((s) => s.origin));
    final etas = ref.watch(discoveryProvider.select((s) => s.etas));
    final aedsStatus = ref.watch(aedsProvider.select((s) => s.status));
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final discovery = ref.read(discoveryProvider.notifier);
    final show = showResult(context);

    void onFind() => discovery.findNearest().then(show);
    void onPick() => discovery.startPicking((picked) => discovery.findFrom(picked).then(show));

    final result = search is SearchDone && search.result.status != FindStatus.found ? search.result : null;
    final failed = search is SearchFailed;
    if (!OriginIssueNotice.shows(issue) && !failed && result == null && aedsStatus != LoadStatus.error) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s24,
        children: [
          if (OriginIssueNotice.shows(issue)) OriginIssueNotice(issue: issue!, onPick: onPick, onRetry: onFind),
          if (failed)
            DefiNotice(
              tone: Tone.danger,
              title: 'Nie udało się wyznaczyć trasy.',
              actions: [DefiButton(label: 'Spróbuj ponownie', onPressed: onFind)],
            ),
          if (result != null) ...[
            DefiNotice(
              tone: Tone.warning,
              title: result.status == FindStatus.routingUnavailable
                  ? 'Nie udało się wyznaczyć trasy.'
                  : 'Nie znaleźliśmy AED dostępnego według danych.',
              child: Text(
                'Sprawdziliśmy ${result.evaluatedCount} defibrylatorów w promieniu ${formatDistance(result.searchedRadiusM)}.',
              ),
            ),
            if (result.unknownAccessAlternatives.isNotEmpty)
              AedList(
                title: 'Dostęp niepotwierdzony',
                aeds: result.unknownAccessAlternatives,
                now: now,
                etas: etas,
                origin: origin,
                onSelect: (aed) => context.go(RoutePaths.aedPath(aed.id)),
              ),
          ],
          if (aedsStatus == LoadStatus.error)
            DefiNotice(
              tone: Tone.danger,
              title: 'Nie udało się wczytać defibrylatorów.',
              actions: [DefiButton(label: 'Spróbuj ponownie', onPressed: ref.read(aedsProvider.notifier).load)],
            ),
        ],
      ),
    );
  }
}

const _deviceCondition = {
  OperationalStatus.unknown: 'Stan urządzenia nie jest potwierdzony. Status dotyczy tylko godzin dostępu.',
  OperationalStatus.confirmedUnavailable: 'Urządzenie jest oznaczone jako niedostępne.',
  OperationalStatus.confirmedOperational: 'Urządzenie zostało sprawdzone.',
};

/// Walking directions in Google Maps; without an origin it uses the device location.
Uri _googleMapsUrl(LngLat destination, LngLat? origin) => Uri.https('www.google.com', '/maps/dir/', {
  'api': '1',
  'destination': '${destination.lat},${destination.lng}',
  'travelmode': 'walking',
  if (origin != null) 'origin': '${origin.lat},${origin.lng}',
});

/// Selected AED card (DESIGN.md §7): time, place, access, entrance, route, details with the photo, report,
/// then the other compared AEDs.
class AedDetailsPanel extends HookConsumerWidget {
  const AedDetailsPanel({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aed = ref.watch(aedsProvider.select((s) => s.byId[id]));
    final aedsStatus = ref.watch(aedsProvider.select((s) => s.status));
    final dataStatus = ref.watch(aedsProvider.select((s) => s.dataStatus));
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final discoveryState = ref.watch(discoveryProvider);
    final discovery = ref.read(discoveryProvider.notifier);
    final DiscoveryState(:origin, :etas, :route, :routing, :search, :issue) = discoveryState;

    useEffect(() {
      if (origin != null) Future.microtask(() => discovery.requestEtas([id]));
      return null;
    }, [id, origin]);

    if (aed == null) {
      return aedsStatus == LoadStatus.error || aedsStatus == LoadStatus.ready
          ? const DefiNotice(tone: Tone.warning, title: 'Nie znaleźliśmy tego defibrylatora.')
          : const DefiLoadingText('Wczytujemy dane…');
    }

    // Alternatives stay visible while the user compares the AEDs of the last search.
    final result = search is SearchDone ? search.result : null;
    final compared = [
      if (result != null) ...[?result.selected?.aed, ...result.alternatives.map((c) => c.aed)],
    ];
    final inResult = compared.any((a) => a.id == aed.id);
    final fastest = result?.selected?.aed.id == aed.id;
    final routeShown = route?.aedId == aed.id;
    final routingState = routing?.aedId == aed.id ? routing!.status : null;
    final straightLineM = origin == null ? null : distanceMeters(origin, aed.location);
    void select(Aed other) => context.go(RoutePaths.aedPath(other.id));
    final others = compared.where((a) => a.id != aed.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            if (fastest) const DefiText('Najszybszy z porównanych', variant: TextVariant.label, tone: TextTone.accent),
            if (etas[aed.id] != null) TravelTime(hero: true, eta: etas[aed.id]),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.s4,
              children: [
                DefiText(aed.venueName, variant: TextVariant.name),
                DefiText(aed.address, tone: TextTone.secondary),
              ],
            ),
          ],
        ),
        AedStatusView(status: aedStatus(aed, now)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s4,
          children: [
            const DefiText('Wejście', variant: TextVariant.heading),
            DefiText(aed.entrance ?? 'Brak informacji o wejściu.'),
            DefiText(placementLabel(aed), tone: TextTone.secondary),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            if (routeShown) ...[
              DefiButton(
                variant: ButtonVariant.primary,
                icon: AppIconName.navigation,
                label: 'Prowadź do defibrylatora',
                onPressed: () => context.go(RoutePaths.navigatePath(aed.id)),
              ),
              DefiButton(
                icon: AppIconName.googleMaps,
                label: 'Otwórz w Google Maps',
                onPressed: () => launchUrl(_googleMapsUrl(aed.location, origin), mode: LaunchMode.externalApplication),
              ),
            ] else
              DefiButton(
                variant: ButtonVariant.primary,
                icon: AppIconName.directionsWalk,
                loading: routingState == RoutingStatus.loading,
                loadingLabel: 'Wyznaczamy trasę…',
                label: 'Wyznacz trasę',
                onPressed: () => discovery.routeTo(aed.id),
              ),
            if (routingState == RoutingStatus.failed)
              DefiNotice(
                tone: Tone.danger,
                title: 'Nie udało się wyznaczyć trasy.',
                actions: [DefiButton(label: 'Spróbuj ponownie', onPressed: () => discovery.routeTo(aed.id))],
                child: straightLineM == null
                    ? null
                    : Text('Odległość w linii prostej: ${formatDistance(straightLineM)}.'),
              ),
            if (OriginIssueNotice.shows(issue))
              OriginIssueNotice(
                issue: issue!,
                onPick: () => discovery.startPicking((_) => discovery.routeTo(aed.id)),
                onRetry: () => discovery.routeTo(aed.id),
              ),
          ],
        ),
        Column(
          children: [
            const DefiDisclosure(
              title: 'Jak użyć defibrylatora',
              children: [AedUsageGuide(withHeading: false, onCall: callEmergency)],
            ),
            DefiDisclosure(
              title: 'Godziny dostępu',
              children: [
                AedHours(schedule: aed.schedule, sourceHours: aed.sourceHours, unverified: aed.unverifiedSchedule),
              ],
            ),
            // On a phone the photo waits in the source details to keep the card short; the guide shows it on the way.
            DefiDisclosure(
              title: 'Informacje ze źródła',
              children: [
                DefiText(aed.sourceHours ?? 'Źródło nie podaje godzin.'),
                AedPhoto(aed: aed),
              ],
            ),
            DefiDisclosure(
              title: 'Urządzenie i dane',
              last: true,
              children: [
                DefiText(_deviceCondition[aed.operationalStatus]!),
                if (aed.source == AedSource.osm)
                  const DefiText(
                    'Punkt spoza rejestru miasta: dane z OpenStreetMap, nieoficjalne.',
                    tone: TextTone.secondary,
                  ),
                if (aed.hoursSource == HoursSource.osm)
                  const DefiText('Godziny z OpenStreetMap.', tone: TextTone.secondary),
                if (aed.hoursSource == HoursSource.cityOsm)
                  const DefiText('Godziny z rejestru miasta, potwierdzone w OpenStreetMap.', tone: TextTone.secondary),
                if (dataStatus != null) ...[
                  DefiText(
                    'Dane pobrano: ${formatDateTime(dataStatus.fetchedAt)}',
                    variant: TextVariant.meta,
                    tone: TextTone.muted,
                  ),
                  DefiText(dataStatus.attribution, variant: TextVariant.meta, tone: TextTone.muted),
                ],
              ],
            ),
          ],
        ),
        DefiButton(
          icon: AppIconName.flag,
          label: 'Zgłoś problem',
          onPressed: () => context.go(RoutePaths.reportPath(aed.id)),
        ),
        if (result != null && inResult) ...[
          if (others.isNotEmpty)
            AedList(title: 'Inne defibrylatory', aeds: others, now: now, etas: etas, origin: origin, onSelect: select),
          if (result.unknownAccessAlternatives.isNotEmpty)
            AedList(
              title: 'Dostęp niepotwierdzony',
              aeds: result.unknownAccessAlternatives,
              now: now,
              etas: etas,
              origin: origin,
              onSelect: select,
            ),
        ],
      ],
    );
  }
}

const _pageSize = 20;

/// Complete list access to every AED, without operating the map (DESIGN.md §7).
class NearbyListPanel extends HookConsumerWidget {
  const NearbyListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aeds = ref.watch(aedsProvider.select((s) => s.aeds));
    final aedsStatus = ref.watch(aedsProvider.select((s) => s.status));
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final origin = ref.watch(discoveryProvider.select((s) => s.origin));
    final etas = ref.watch(discoveryProvider.select((s) => s.etas));
    final locating = ref.watch(discoveryProvider.select((s) => s.locating));
    final issue = ref.watch(discoveryProvider.select((s) => s.issue));
    final discovery = ref.read(discoveryProvider.notifier);
    final limit = useState(_pageSize);

    final sorted = useMemoized(() {
      final from = origin ?? warsawCenter;
      return [...aeds]..sort((a, b) => distanceMeters(from, a.location).compareTo(distanceMeters(from, b.location)));
    }, [aeds, origin]);
    final shown = sorted.take(limit.value).toList();
    final shownKey = shown.map((a) => a.id).join(',');

    useEffect(() {
      if (origin != null && shownKey.isNotEmpty) Future.microtask(() => discovery.requestEtas(shownKey.split(',')));
      return null;
    }, [origin, shownKey]);

    final available = shown.where((a) => aedStatus(a, now).available).toList();
    final others = shown.where((a) => !aedStatus(a, now).available).toList();
    void select(Aed aed) => context.go(RoutePaths.aedPath(aed.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        const DefiText('Defibrylatory w pobliżu', variant: TextVariant.title),
        if (origin == null)
          DefiNotice(
            title: 'Kolejność od centrum Warszawy.',
            actions: [
              DefiButton(
                icon: AppIconName.myLocation,
                loading: locating,
                loadingLabel: 'Ustalamy lokalizację…',
                label: 'Użyj mojej lokalizacji',
                onPressed: discovery.locate,
              ),
              DefiButton(
                icon: AppIconName.locationOn,
                label: 'Wybierz punkt na mapie',
                onPressed: discovery.startPicking,
              ),
            ],
            child: const Text('Ustal punkt startowy, aby zobaczyć czas dojścia.'),
          ),
        if (OriginIssueNotice.shows(issue))
          OriginIssueNotice(issue: issue!, onPick: discovery.startPicking, onRetry: discovery.locate),
        if (aedsStatus != LoadStatus.ready && aedsStatus != LoadStatus.error) const DefiLoadingText('Wczytujemy dane…'),
        if (available.isNotEmpty)
          AedList(title: 'Dostępne teraz', aeds: available, now: now, etas: etas, origin: origin, onSelect: select),
        if (others.isNotEmpty)
          AedList(
            title: 'Zamknięte i niedostępne',
            aeds: others,
            now: now,
            etas: etas,
            origin: origin,
            onSelect: select,
          ),
        if (limit.value < sorted.length) DefiButton(label: 'Pokaż więcej', onPressed: () => limit.value += _pageSize),
      ],
    );
  }
}
