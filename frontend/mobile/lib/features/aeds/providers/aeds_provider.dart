import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/services/aed_service.dart';

enum LoadStatus { idle, loading, ready, error }

class AedsState {
  const AedsState({
    this.status = LoadStatus.idle,
    this.aeds = const [],
    this.byId = const {},
    this.dataStatus,
    required this.now,
    this.live = true,
    this.pickerOpen = false,
  });

  final LoadStatus status;
  final List<Aed> aeds;
  final Map<String, Aed> byId;
  final DataStatus? dataStatus;

  /// Evaluation time for hours; ticks every minute while [live], otherwise the time picked on the map.
  final DateTime now;
  final bool live;

  /// The one time picker for the map (clock button, coverage panel).
  final bool pickerOpen;

  AedsState copyWith({
    LoadStatus? status,
    List<Aed>? aeds,
    Map<String, Aed>? byId,
    DataStatus? dataStatus,
    DateTime? now,
    bool? live,
    bool? pickerOpen,
  }) => AedsState(
    status: status ?? this.status,
    aeds: aeds ?? this.aeds,
    byId: byId ?? this.byId,
    dataStatus: dataStatus ?? this.dataStatus,
    now: now ?? this.now,
    live: live ?? this.live,
    pickerOpen: pickerOpen ?? this.pickerOpen,
  );
}

class AedsNotifier extends Notifier<AedsState> {
  Timer? _clock;

  @override
  AedsState build() {
    ref.onDispose(() => _clock?.cancel());
    return AedsState(now: DateTime.now());
  }

  Future<void> load() async {
    if (state.status == LoadStatus.loading || state.status == LoadStatus.ready) return;
    state = state.copyWith(status: LoadStatus.loading);
    _clock ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (state.live) state = state.copyWith(now: DateTime.now());
    });
    final service = ref.read(aedServiceProvider);
    try {
      final (aeds, dataStatus) = await (service.fetchAeds(), service.fetchDataStatus()).wait;
      state = state.copyWith(
        status: LoadStatus.ready,
        aeds: aeds,
        byId: {for (final aed in aeds) aed.id: aed},
        dataStatus: dataStatus,
      );
    } catch (_) {
      state = state.copyWith(status: LoadStatus.error);
    }
  }

  /// Preview AED availability at another time; finding and routing still use the real clock.
  void setViewTime(DateTime at) => state = state.copyWith(now: at, live: false);

  void resetViewTime() => state = state.copyWith(now: DateTime.now(), live: true);

  void setTimePickerOpen(bool open) => state = state.copyWith(pickerOpen: open);
}

final aedsProvider = NotifierProvider<AedsNotifier, AedsState>(AedsNotifier.new);

/// Which AED groups the map shows. Only the open ones by default; with every group off, all AEDs show.
/// The selected AED always stays visible.
class MapFiltersNotifier extends Notifier<AedFilters> {
  @override
  AedFilters build() => (available: true, unavailable: false);

  void toggle(AedAvailability group) => state = switch (group) {
    AedAvailability.available => (available: !state.available, unavailable: state.unavailable),
    AedAvailability.unavailable => (available: state.available, unavailable: !state.unavailable),
  };
}

final mapFiltersProvider = NotifierProvider<MapFiltersNotifier, AedFilters>(MapFiltersNotifier.new);
