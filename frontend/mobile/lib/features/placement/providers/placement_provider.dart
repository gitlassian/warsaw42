import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/placement/lib/placement_slots.dart';
import 'package:defiwawa/features/placement/models/placement.dart';
import 'package:defiwawa/features/placement/services/placement_service.dart';

enum PlacementStatus { idle, loading, ready, error }

const _keep = Object();

class PlacementState {
  const PlacementState({
    this.status = PlacementStatus.idle,
    this.data,
    this.mode = PlacementMode.newSites,
    this.count = 10,
    this.selected,
  });

  final PlacementStatus status;
  final PlacementData? data;
  final PlacementMode mode;

  /// How many of the ranked steps the map and the list show.
  final int count;

  /// Rank of the pick highlighted in the list and on the map.
  final int? selected;

  PlacementState copyWith({
    PlacementStatus? status,
    PlacementData? data,
    PlacementMode? mode,
    int? count,
    Object? selected = _keep,
  }) => PlacementState(
    status: status ?? this.status,
    data: data ?? this.data,
    mode: mode ?? this.mode,
    count: count ?? this.count,
    selected: selected == _keep ? this.selected : selected as int?,
  );
}

class PlacementNotifier extends Notifier<PlacementState> {
  @override
  PlacementState build() => const PlacementState();

  Future<void> load() async {
    if (state.status == PlacementStatus.loading || state.status == PlacementStatus.ready) return;
    state = state.copyWith(status: PlacementStatus.loading);
    try {
      final data = await ref.read(placementServiceProvider).fetchPlacement();
      state = state.copyWith(status: PlacementStatus.ready, data: data);
    } catch (_) {
      state = state.copyWith(status: PlacementStatus.error);
    }
  }

  void setMode(PlacementMode mode) => state = state.copyWith(mode: mode, selected: null);

  void setCount(int count) => state = state.copyWith(count: count.clamp(1, placementMaxSteps), selected: null);

  void select(int? rank) => state = state.copyWith(selected: rank);
}

final placementProvider = NotifierProvider<PlacementNotifier, PlacementState>(PlacementNotifier.new);

/// The picks for the time shown on the map (live: the clock) and the chosen mode and count.
final placementViewProvider = Provider<PlacementView?>((ref) {
  final data = ref.watch(placementProvider.select((s) => s.data));
  final mode = ref.watch(placementProvider.select((s) => s.mode));
  final count = ref.watch(placementProvider.select((s) => s.count));
  final now = ref.watch(aedsProvider.select((s) => s.now));
  if (data == null) return null;
  final (:day, :minutes) = warsawClock(now);
  return placementView(data, day: day, minutes: minutes, mode: mode, count: count);
});
