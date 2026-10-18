import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/app/router/route_paths.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/report/models/report.dart';
import 'package:defiwawa/features/report/providers/report_provider.dart';

const _errorMessages = {
  'rate_limited': 'Wysłano zbyt wiele zgłoszeń. Spróbuj ponownie później.',
  'network': 'Nie udało się połączyć. Zgłoszenie jest zachowane, spróbuj ponownie.',
};

/// "Zgłoś problem" (DESIGN.md §9): form, confirmation. No login or profile.
class ReportPanel extends HookConsumerWidget {
  const ReportPanel({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aed = ref.watch(aedsProvider.select((s) => s.byId[id]));
    final reports = ref.read(reportProvider.notifier);
    final flow = ref.watch(reportProvider.select((s) => s[id])) ?? reports.flow(id);
    final fieldErrors = useState<DraftErrors>((category: null, description: null));
    final ReportFlow(:draft, :busy, :error) = flow;

    useEffect(() {
      Future.microtask(() => reports.open(id));
      return null;
    }, [id]);

    void onSubmit() {
      if (busy) return;
      final errors = validateDraft(draft);
      fieldErrors.value = errors;
      if (errors.category == null && errors.description == null) reports.submit(id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s4,
          children: [
            const DefiText('Zgłoś problem', variant: TextVariant.title),
            if (aed != null) DefiText('${aed.venueName}, ${aed.address}', tone: TextTone.secondary),
          ],
        ),
        if (flow.step == ReportStep.form) ...[
          DefiChoiceGroup<ReportCategory>(
            legend: 'Rodzaj problemu',
            options: [for (final c in ReportCategory.values) (value: c, label: c.label)],
            value: draft.category,
            error: fieldErrors.value.category,
            onChanged: (value) {
              reports.updateDraft(id, category: value);
              fieldErrors.value = (category: null, description: fieldErrors.value.description);
            },
          ),
          DefiTextField(
            multiline: true,
            label: 'Opis',
            hint: 'Co się stało? Np. szafka jest zamknięta albo godziny są inne.',
            value: draft.description,
            maxLength: descriptionMax,
            error: fieldErrors.value.description,
            onChanged: (value) {
              reports.updateDraft(id, description: value);
              fieldErrors.value = (category: fieldErrors.value.category, description: null);
            },
          ),
          if (error != null) DefiNotice(tone: Tone.danger, title: _errorMessages[error] ?? _errorMessages['network']!),
          DefiButton(
            variant: ButtonVariant.primary,
            loading: busy,
            loadingLabel: 'Wysyłamy zgłoszenie…',
            label: 'Wyślij zgłoszenie',
            onPressed: onSubmit,
          ),
        ],
        if (flow.step == ReportStep.done)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.s16,
            children: [
              const DefiNotice(
                tone: Tone.accent,
                title: 'Dziękujemy. Zgłoszenie czeka na sprawdzenie.',
                child: Text('Zgłoszenie nie zmienia od razu statusu defibrylatora.'),
              ),
              DefiButton(
                variant: ButtonVariant.primary,
                label: 'Wróć do AED',
                onPressed: () {
                  reports.reset(id);
                  context.go(RoutePaths.aedPath(id));
                },
              ),
            ],
          ),
      ],
    );
  }
}
