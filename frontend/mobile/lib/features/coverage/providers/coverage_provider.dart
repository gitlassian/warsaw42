import 'dart:isolate';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/geo/warsaw_boundary.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/aeds/services/aed_service.dart';
import 'package:defiwawa/features/coverage/lib/coverage_geometry.dart';
import 'package:defiwawa/features/coverage/models/coverage.dart';

// shortcut: client-side stand-in for GET /coverage (ENDPOINTS.md §5, PLAN.md §9), as on web: circles of the threshold
// radius (straight line) around the eligible AEDs, merged into regions. Replace with the precomputed backend layer.
Future<CoverageLayer> _computeCoverage(
  List<Aed> aeds,
  CoverageScenario scenario,
  double thresholdM,
  DateTime at,
) async {
  // Every scenario excludes confirmed unavailable and non-public devices.
  final sites = <Site>[
    for (final a in aeds)
      if (a.publicAccess == PublicAccess.public &&
          a.operationalStatus != OperationalStatus.confirmedUnavailable &&
          switch (scenario) {
            CoverageScenario.allPublic => true,
            CoverageScenario.alwaysOpen => a.schedule is AlwaysOpen,
            CoverageScenario.availableAt => evaluateHours(a.schedule, at) is HoursOpen,
          })
        (id: a.id, lng: a.location.lng, lat: a.location.lat),
  ];
  // Hundreds of circles merge in a background isolate, so the map keeps moving.
  final features = await Isolate.run(() => coverageAreas(warsawBoundary, sites, thresholdM));
  return CoverageLayer(
    scenario: scenario,
    thresholdM: thresholdM,
    eligible: sites,
    data: {'type': 'FeatureCollection', 'features': features},
  );
}

enum CoverageStatus { idle, loading, ready, error }

const _keep = Object();

class CoverageState {
  const CoverageState({
    this.scenario = CoverageScenario.availableAt,
    this.thresholdM = 500,
    this.status = CoverageStatus.idle,
    this.layer,
    this.selected,
  });

  final CoverageScenario scenario;

  /// PLAN.md §9 planning assumption, not an emergency-response standard.
  final double thresholdM;
  final CoverageStatus status;

  /// Stays visible while a newer layer is calculated.
  final CoverageLayer? layer;
  final CoverageCell? selected;

  CoverageState copyWith({
    CoverageScenario? scenario,
    double? thresholdM,
    CoverageStatus? status,
    CoverageLayer? layer,
    Object? selected = _keep,
  }) => CoverageState(
    scenario: scenario ?? this.scenario,
    thresholdM: thresholdM ?? this.thresholdM,
    status: status ?? this.status,
    layer: layer ?? this.layer,
    selected: selected == _keep ? this.selected : selected as CoverageCell?,
  );
}

class CoverageNotifier extends Notifier<CoverageState> {
  int _requestToken = 0;

  @override
  CoverageState build() => const CoverageState();

  Future<void> load() async {
    final CoverageState(:scenario, :thresholdM) = state;
    // The time-based scenario uses the one map time (live: the clock).
    final at = ref.read(aedsProvider).now;
    final token = ++_requestToken;
    state = state.copyWith(status: CoverageStatus.loading, selected: null);
    try {
      final aeds = await ref.read(aedServiceProvider).fetchAeds();
      final layer = await _computeCoverage(aeds, scenario, thresholdM, at);
      if (token == _requestToken) state = state.copyWith(status: CoverageStatus.ready, layer: layer);
    } catch (_) {
      if (token == _requestToken) state = state.copyWith(status: CoverageStatus.error);
    }
  }

  void setQuery({CoverageScenario? scenario, double? thresholdM}) {
    state = state.copyWith(scenario: scenario, thresholdM: thresholdM);
    load();
  }

  void selectCell(CoverageCell? cell) => state = state.copyWith(selected: cell);
}

final coverageProvider = NotifierProvider<CoverageNotifier, CoverageState>(CoverageNotifier.new);
