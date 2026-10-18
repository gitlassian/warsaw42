/// POST /reports categories (ENDPOINTS.md §4) with their interface labels (DESIGN.md §9).
enum ReportCategory {
  missing('Brak AED'),
  malfunction('Problem z urządzeniem'),
  inaccessible('Brak dostępu'),
  incorrectHours('Błędne godziny'),
  incorrectLocation('Błędna lokalizacja'),
  other('Inny problem');

  const ReportCategory(this.label);
  final String label;

  String get apiValue => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}

const descriptionMin = 10;
const descriptionMax = 2000;

class ReportDraft {
  const ReportDraft({this.category, this.description = ''});

  final ReportCategory? category;
  final String description;
}

typedef DraftErrors = ({String? category, String? description});

DraftErrors validateDraft(ReportDraft draft) {
  final length = draft.description.trim().length;
  return (
    category: draft.category == null ? 'Wybierz rodzaj problemu.' : null,
    description: length < descriptionMin
        ? 'Opisz problem w co najmniej $descriptionMin znakach.'
        : length > descriptionMax
        ? 'Opis może mieć najwyżej $descriptionMax znaków.'
        : null,
  );
}
