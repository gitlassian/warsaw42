// `app_data.placement` (backend/pipeline/placement.py): where an AED helps most, for every half hour of the week.

/// One ranked step: a candidate (or AED) index, the residents it brings within reach (and those aged 65+),
/// and the share of residents within reach once it and every step before it are added.
typedef PlacementStep = ({int index, int gain, int gain65, double cumulativePct});

class PlacementSlot {
  const PlacementSlot({
    required this.openAeds,
    required this.coveredPct,
    required this.uncovered,
    required this.uncovered65,
    required this.newSites,
    required this.convert,
  });

  factory PlacementSlot.fromJson(Map<String, dynamic> json) {
    List<PlacementStep> steps(Object? list) => [
      for (final step in list as List)
        (
          index: (step[0] as num).toInt(),
          gain: (step[1] as num).toInt(),
          gain65: (step[2] as num).toInt(),
          cumulativePct: (step[3] as num).toDouble(),
        ),
    ];
    return PlacementSlot(
      openAeds: (json['a'] as num).toInt(),
      coveredPct: (json['c'] as num).toDouble(),
      uncovered: (json['u'] as num).toInt(),
      uncovered65: (json['u65'] as num).toInt(),
      newSites: steps(json['n']),
      convert: steps(json['v']),
    );
  }

  /// Open AEDs at that moment.
  final int openAeds;

  /// Residents within reach of an open AED, percent.
  final double coveredPct;

  /// Residents without reach, and those aged 65+.
  final int uncovered;
  final int uncovered65;

  /// Ranked steps: new addresses, and existing closed AEDs to open around the clock.
  final List<PlacementStep> newSites;
  final List<PlacementStep> convert;
}

class PlacementData {
  const PlacementData({
    required this.radiusM,
    required this.slotMinutes,
    required this.costPerAedPln,
    required this.costBasis,
    required this.candidates,
    required this.aeds,
    required this.slots,
  });

  factory PlacementData.fromJson(Map<String, dynamic> json) => PlacementData(
    radiusM: (json['radius_m'] as num).toDouble(),
    slotMinutes: (json['slot_minutes'] as num).toInt(),
    costPerAedPln: (json['cost_per_aed_pln'] as num).toInt(),
    costBasis: json['cost_basis'] as String,
    candidates: [
      for (final c in json['candidates'] as List)
        (lng: (c[0] as num).toDouble(), lat: (c[1] as num).toDouble(), address: c[2] as String),
    ],
    aeds: [
      for (final a in json['aeds'] as List)
        (name: a[1] as String, address: a[2] as String, lng: (a[3] as num).toDouble(), lat: (a[4] as num).toDouble()),
    ],
    slots: [for (final s in json['slots'] as List) PlacementSlot.fromJson(s as Map<String, dynamic>)],
  );

  final double radiusM;
  final int slotMinutes;
  final int costPerAedPln;
  final String costBasis;
  final List<({double lng, double lat, String address})> candidates;
  final List<({String name, String address, double lng, double lat})> aeds;
  final List<PlacementSlot> slots;
}

enum PlacementMode {
  newSites('Nowe AED w nowych miejscach'),
  convert('Istniejące AED, zamknięte o tej porze: udostępnić całodobowo');

  const PlacementMode(this.label);

  final String label;
}

const placementMaxSteps = 20;

class PlacementPick {
  const PlacementPick({
    required this.rank,
    required this.lng,
    required this.lat,
    required this.title,
    required this.address,
    required this.gain,
    required this.gain65,
    required this.cumulativePct,
  });

  final int rank;
  final double lng;
  final double lat;
  final String title;
  final String address;

  /// Residents newly within reach, and those aged 65+.
  final int gain;
  final int gain65;
  final double cumulativePct;
}

class PlacementView {
  const PlacementView({
    required this.slot,
    required this.picks,
    required this.gainPct,
    required this.gainPeople,
    required this.coveredPctAfter,
  });

  final PlacementSlot slot;
  final List<PlacementPick> picks;

  /// Percentage points of residents the shown picks add, and the number of residents.
  final double gainPct;
  final int gainPeople;
  final double coveredPctAfter;
}
