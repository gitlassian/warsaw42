import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/presentation/widgets/aed_widgets.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

/// Walking time "4 min pieszo · 280 m"; never presents straight-line distance as walking.
class TravelTime extends StatelessWidget {
  const TravelTime({super.key, this.eta, this.straightLineM, this.hero = false});

  final EtaEntry? eta;

  /// Shown only when there is no walking time, always labeled as straight-line.
  final double? straightLineM;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    const tabular = [FontFeature.tabularFigures()];
    final time = hero
        ? AppTextStyles.time
        : AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular);
    final note = AppTextStyles.body.copyWith(color: AppColors.textSecondary);
    const gap = WidgetSpan(child: SizedBox(width: AppSpacing.s8));
    final spans = switch (eta) {
      EtaLoading() => null,
      EtaOk(:final durationSeconds, :final distanceM) => [
        TextSpan(text: '${formatDuration(durationSeconds)} pieszo', style: time),
        gap,
        TextSpan(
          text: '· ${formatDistance(distanceM)}',
          style: AppTextStyles.body.copyWith(fontFeatures: tabular),
        ),
      ],
      EtaFailed() => [
        TextSpan(text: '—', style: time, semanticsLabel: ''),
        gap,
        TextSpan(text: 'Nie udało się obliczyć czasu', style: note),
      ],
      null => [
        TextSpan(
          text: formatDistance(straightLineM ?? 0),
          style: AppTextStyles.label.copyWith(fontFeatures: tabular),
        ),
        TextSpan(text: ' w linii prostej', style: note),
      ],
    };
    if (spans == null) {
      return Semantics(
        label: 'Obliczamy czas dojścia',
        child: Container(
          width: hero ? 160 : 96,
          height: hero ? 32 : 16,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          decoration: const BoxDecoration(color: AppColors.unknownSoft, borderRadius: AppRadius.pill),
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: spans,
        style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

/// Titled list of AED rows; selecting a row opens its card and marker. Callers skip empty lists.
class AedList extends StatelessWidget {
  const AedList({
    super.key,
    required this.title,
    required this.aeds,
    required this.now,
    required this.etas,
    required this.origin,
    required this.onSelect,
    this.selectedId,
  });

  final String title;
  final List<Aed> aeds;
  final DateTime now;
  final Map<String, EtaEntry> etas;

  /// Without an origin the rows show no time or distance (DESIGN.md §7).
  final LngLat? origin;
  final ValueChanged<Aed> onSelect;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final origin = this.origin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s4,
      children: [
        DefiText(title, variant: TextVariant.heading),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final aed in aeds)
              AedListItem(
                aed: aed,
                status: aedStatus(aed, now),
                selected: aed.id == selectedId,
                onTap: () => onSelect(aed),
                travel: origin == null
                    ? null
                    : TravelTime(eta: etas[aed.id], straightLineM: distanceMeters(origin, aed.location)),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Znajdź najbliższy defibrylator": pinned on every screen, outside the sheet.
class FindButton extends StatelessWidget {
  const FindButton({super.key, required this.searching, required this.onFind, required this.onCancel});

  final bool searching;
  final VoidCallback onFind;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s8,
      children: [
        DefiButton(
          variant: ButtonVariant.primary,
          icon: AppIconName.aed,
          loading: searching,
          loadingLabel: 'Szukamy defibrylatora…',
          label: 'Znajdź najbliższy defibrylator',
          onPressed: onFind,
        ),
        if (searching) DefiButton(label: 'Anuluj', onPressed: onCancel),
      ],
    );
  }
}

const _issueMessages = {
  LocationIssue.denied: (
    'Nie możemy ustalić Twojej lokalizacji.',
    'Dostęp do lokalizacji jest wyłączony. Możesz wybrać punkt startowy na mapie.',
  ),
  LocationIssue.unavailable: (
    'Nie możemy ustalić Twojej lokalizacji.',
    'Sprawdź, czy lokalizacja jest włączona w ustawieniach urządzenia, i spróbuj ponownie. Możesz też wybrać punkt startowy na mapie.',
  ),
  LocationIssue.outside: (
    'Aplikacja obejmuje Warszawę.',
    'Twoja lokalizacja jest poza miastem. Wybierz punkt startowy w Warszawie.',
  ),
};

/// Location problem with the manual-origin fallback (DESIGN.md §8). A picked point outside Warsaw is
/// explained by the pick banner instead, so callers show this only for [shows] issues.
class OriginIssueNotice extends StatelessWidget {
  const OriginIssueNotice({super.key, required this.issue, required this.onPick, this.onRetry});

  final LocationIssue issue;
  final VoidCallback onPick;

  /// Shown for a failed fix, which often succeeds on a second try.
  final VoidCallback? onRetry;

  static bool shows(LocationIssue? issue) => issue != null && issue != LocationIssue.outsidePick;

  @override
  Widget build(BuildContext context) {
    final (title, text) = _issueMessages[issue]!;
    return DefiNotice(
      tone: Tone.warning,
      title: title,
      actions: [
        if (issue == LocationIssue.unavailable && onRetry != null)
          DefiButton(icon: AppIconName.myLocation, label: 'Spróbuj ponownie', onPressed: onRetry),
        DefiButton(icon: AppIconName.locationOn, label: 'Wybierz punkt na mapie', onPressed: onPick),
      ],
      child: Text(text),
    );
  }
}

/// Shown over the map while the user picks a start point.
class PickOriginBanner extends StatelessWidget {
  const PickOriginBanner({super.key, required this.outside, required this.onCancel});

  /// The last tapped point was outside Warsaw.
  final bool outside;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s8, AppSpacing.s8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.control,
          boxShadow: AppShadows.floating,
        ),
        child: Row(
          spacing: AppSpacing.s8,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DefiText('Wybierz punkt na mapie', variant: TextVariant.label),
                  Text(
                    outside
                        ? 'Ten punkt jest poza Warszawą. Wybierz punkt w granicach miasta.'
                        : 'Dotknij mapy w miejscu startu.',
                    style: AppTextStyles.body.copyWith(color: outside ? AppColors.danger : AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            DefiIconButton(icon: AppIconName.close, label: 'Anuluj wybór punktu', onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}

const _minLength = 3;
const _debounce = Duration(milliseconds: 300);

sealed class _Lookup {
  const _Lookup();
}

final class _Idle extends _Lookup {
  const _Idle();
}

final class _Loading extends _Lookup {
  const _Loading();
}

final class _Failed extends _Lookup {
  const _Failed();
}

final class _Done extends _Lookup {
  const _Done(this.hits);
  final List<AddressHit> hits;
}

/// Top of the phone screen: the nearest AED from a typed Warsaw address, a manual start point like one picked on the map.
class AddressSearch extends HookWidget {
  const AddressSearch({super.key, required this.onSearch, required this.onChoose, required this.onPickOnMap});

  final Future<List<AddressHit>> Function(String query) onSearch;
  final ValueChanged<AddressHit> onChoose;
  final VoidCallback onPickOnMap;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final focus = useFocusNode();
    final focused = useListenable(focus).hasFocus;
    final query = useValueListenable(controller).text;
    final lookup = useState<_Lookup>(const _Idle());
    final open = useState(false);
    // The chosen address fills the field; it is not searched again.
    final chosen = useState<String?>(null);

    final trimmed = query.trim();
    useEffect(() {
      if (trimmed.length < _minLength || trimmed == chosen.value) return null;
      var cancelled = false;
      final timer = Timer(_debounce, () {
        lookup.value = const _Loading();
        onSearch(trimmed).then(
          (hits) {
            if (!cancelled) lookup.value = _Done(hits);
          },
          onError: (Object _) {
            if (!cancelled) lookup.value = const _Failed();
          },
        );
      });
      return () {
        cancelled = true;
        timer.cancel();
      };
    }, [trimmed, chosen.value]);

    final hits = switch (lookup.value) {
      _Done(:final hits) => hits,
      _ => const <AddressHit>[],
    };
    final showList = open.value && trimmed.length >= _minLength && trimmed != chosen.value && lookup.value is! _Idle;

    void choose(AddressHit hit) {
      chosen.value = hit.name;
      controller.text = hit.name;
      open.value = false;
      focus.unfocus();
      onChoose(hit);
    }

    void clear() {
      chosen.value = null;
      controller.clear();
      lookup.value = const _Idle();
    }

    final message = switch (lookup.value) {
      _Loading() => 'Szukamy…',
      _Done(hits: []) => 'Nie znaleźliśmy tego adresu w Warszawie.',
      _Failed() => 'Nie udało się wyszukać adresu.',
      _ => null,
    };

    return TapRegion(
      onTapOutside: (_) {
        open.value = false;
        focus.unfocus();
      },
      child: _FocusRing(
        shown: focused,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            // The radius of the buttons around it.
            borderRadius: AppRadius.control,
            boxShadow: AppShadows.floating,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s12, right: AppSpacing.s4),
                child: Row(
                  spacing: AppSpacing.s8,
                  children: [
                    // Like Google Maps: the brand mark sits at the start of the field, the magnifier at its end.
                    SvgPicture.asset('assets/brand/defiwawa-symbol.svg', width: 28, height: 28),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: Semantics(
                          label: 'Adres',
                          child: TextField(
                            controller: controller,
                            focusNode: focus,
                            textInputAction: TextInputAction.search,
                            autocorrect: false,
                            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                            cursorColor: AppColors.accent,
                            onTap: () => open.value = true,
                            onChanged: (_) {
                              chosen.value = null;
                              open.value = true;
                            },
                            onSubmitted: (_) {
                              if (showList && hits.isNotEmpty) choose(hits.first);
                            },
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              hintText: 'Szukaj adresu',
                              hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (query.isNotEmpty)
                      DefiIconButton(icon: AppIconName.close, label: 'Wyczyść adres', onPressed: clear),
                    DefiIconButton(
                      icon: AppIconName.search,
                      label: 'Szukaj',
                      onPressed: () => hits.isNotEmpty ? choose(hits.first) : open.value = true,
                    ),
                  ],
                ),
              ),
              if (showList)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final hit in hits)
                        Semantics(
                          button: true,
                          child: InkWell(
                            onTap: () => choose(hit),
                            highlightColor: AppColors.accentSoft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12, horizontal: AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DefiText(hit.name, variant: TextVariant.label),
                                  if (hit.detail != null) DefiText(hit.detail!, tone: TextTone.secondary),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (message != null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12, horizontal: AppSpacing.s16),
                            child: DefiText(message, tone: TextTone.secondary),
                          ),
                        ),
                      if (lookup.value is _Failed || (lookup.value is _Done && hits.isEmpty))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s16),
                          child: DefiButton(
                            icon: AppIconName.locationOn,
                            label: 'Wybierz punkt na mapie',
                            onPressed: () {
                              open.value = false;
                              focus.unfocus();
                              onPickOnMap();
                            },
                          ),
                        ),
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

/// The web focus ring (DESIGN.md §7) around a card with the control radius: a 2-wide outline 2 outside it, the gap white.
class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (shown)
          Positioned.fill(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.focus, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.surface, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
