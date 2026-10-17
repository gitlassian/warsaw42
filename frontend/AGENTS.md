# DefiWawa Flutter Architecture & Coding Standards

## 1. Architectural Layers (Feature-First)
We structure our Flutter codebase using a **Feature-Driven Architecture** across Flutter Web and Mobile (Android & iOS). Every feature in `lib/features/[feature_name]/` should be self-contained, modular, and testable.

*   **Models (`/models/`):** Pure data structures with JSON serialization and immutable equality.
    *   *Domain Models:* e.g., `Aed`, `AedAccessSchedule`, `AedLocation`, `WalkingRoute`, `CoverageZone`, `OfflinePackage`. Represent validated, domain-evaluated state.
    *   *Form/Draft Models:* e.g., `ReportFormData`, `ReportDraft`, `OriginSelectionState`, `CoverageFilterState`. Hold transient user input and draft state across navigation or validation steps.
*   **Services & Repositories (`/services/`, `/repositories/`):** Encapsulate external APIs, database operations, and platform logic (Google Maps adapter, offline OSM tile renderer, Supabase Client, Google Routes proxy, Geolocation/GPS, local SQLite storage). Widgets must never invoke HTTP requests, SQLite queries, or platform channels directly.
*   **Presentation / Widgets (`/presentation/widgets/`):**
    *   *Feature Widgets:* Components specific to a single view or interaction of that feature.
    *   *Shared Preview/Summary Widgets:* (e.g., `aed_preview_widgets.dart`) — **Critical reuse layer.** Hosts visual cards, schedule blocks, and badges reused across map bottom sheets, wide-screen side panels, and offline views.
*   **Presentation / Pages & Sheets (`/presentation/pages/`, `/presentation/sheets/`):** Smart container pages and sheet controllers. Responsible for coordinating navigation, handling Riverpod state, managing sheet expansion, and assembling layouts from dumb widgets.

---

## 2. "Dumb Widgets" Principle (Minimum Logic)
Widgets must be highly predictable, focusing solely on rendering visual state.

*   **No Business Logic:** A presentation widget must be unaware of Riverpod containers, Bloc, or raw API clients. It receives data via constructor parameters and bubbles user interactions up via callbacks (`onTap`, `onFindAed`, `onSelectOrigin`, `onRetry`).
*   **Minimal Transformations in `build()`:** Avoid formatting complex data inside `build()`. Delegate travel time formatting (`4 min pieszo · 280 m`), schedule evaluation (`Dostępny według godzin`), opening status badges, and address strings to model getters, extensions, or dedicated formatters.
*   **Prefer Stateless:** Default to `StatelessWidget`. Use `StatefulWidget` (or `HookWidget` / `HookConsumerWidget`) only when managing local animation controllers, sheet draggable snap controllers, text editing controllers, or localized input focus.

---

## 3. Strict Reuse Strategy (Hard Reuse across Responsive Layouts)
Avoid duplicate implementations between mobile bottom sheets and wide-screen side panels.

*   **Responsive Adaptation (<840px vs ≥840px):**
    *   *Narrow screens (<840px):* Interface relies on a single bottom sheet over the map.
    *   *Wide screens (≥840px):* Interface places a 360–420px wide panel on the left and the map on the right.
    *   Both layouts **must reuse the exact same atomic cards and sections** (`AedHeaderCard`, `WalkingTimeBadge`, `EntranceInstructionsBlock`, `AedScheduleSection`, `AlternativesList`).
*   **Data Adaptability:** Visual widgets should accept data types or view models that generalize across both live backend data and cached offline SQLite records (e.g., `AedSummaryViewData`).
*   **Composition over Inheritance:** Assemble complex cards by combining atomic components (`DefiBadge`, `WalkingTimeBadge`, `InfoRow`).
*   **Semantic Integrity:** Never reuse widgets if the underlying business meaning diverges:
    *   *Never* share UI widgets that conflate online walking times (`4 min pieszo`) with offline straight-line distances (`280 m w linii prostej`).
    *   *Never* present scheduled opening hours (`Dostępny według godzin`) as confirmed physical device health.

---

## 4. DefiWawa Design System (Calm, High-Contrast Utility)
Every UI element follows the unified design specification in `DESIGN.md`. DefiWawa is a calm, life-saving civic tool with a primary green accent, large text, and one primary action.

*   **Styling Rules & Geometry:**
    *   Buttons, text fields, cards, and modal dialogs: `BorderRadius.circular(12)`.
    *   Bottom sheet top corners: `BorderRadius.vertical(top: Radius.circular(24))`.
    *   Map walking-time pills & circular controls: Fully rounded (`BorderRadius.circular(999)` or `CircleBorder`).
    *   No harsh brutalism, zero-corner borders, gradients, glows, or decorative colored blocks.
*   **Colors (`AppColors` tokens):**
    *   Accent: `AppColors.accent` (`#237A57`), hover (`#1D6B4B`), pressed (`#185A40`), soft (`#EAF5EE`).
    *   Neutrals: surface (`#FFFFFF`), background (`#F5F8F6`), text primary (`#17231D`), text secondary (`#506158`), text muted (`#5D6E63`).
    *   Borders: decorative (`#D8E2DC`), control outline (`#75857B`), focus ring (`#125A3C`).
    *   Semantics: warning (`#8A570A`, soft `#FFF5DF`), danger (`#B23B36`, soft `#FCEDEC`), unknown (`#56645B`, soft `#EEF2EF`), user location (`#2869B1`).
*   **Typography:**
    *   **Single font family: Noto Sans.** Font files must be bundled locally in app assets so they are available immediately during an offline cold start.
    *   Weights: 400 (body, address, entrance info), 600 (headings, buttons, status badges), 700 (primary travel times and key metrics).
    *   Use tabular figures (`FontFeature.tabularFigures()`) for travel times and distances.
    *   Primary interface language is **Polish** (`Znajdź defibrylator`, `Dostępny według godzin`, `Wejście`, `Zgłoś problem`, etc.). Keep technical jargon (OTP, API, PostGIS, AI) out of UI copy.
*   **Grid & Spacing:** Strictly align layouts using the spacing scale: `4, 8, 12, 16, 24, 32, 48`.
*   **Touch Targets & Heights:**
    *   Primary button: minimum height `56px`.
    *   Secondary button and input fields: minimum height `48px`.
    *   Selection row: minimum height `64px`, expanding with system text scaling.
    *   Interactive icons / controls: minimum hit area of `48 × 48 px`.
*   **Icons:** **Material Symbols Rounded** (`FILL=0`, `wght=500`, `GRAD=0`) via shared `AppIcon`. Do not mix with generic icons, SF Symbols, or emoji.

---

## 5. State Management (Riverpod & Hooks)
We use `flutter_riverpod` (v2 Notifiers) and `flutter_hooks` for reactive state.

*   **Notifiers & Providers:**
    *   Read-only remote data: `FutureProvider` or `StreamProvider` (e.g., `aedDetailsProvider(id)`, `offlinePackagesProvider`).
    *   Interactive flows: Cohesive `Notifier` / `AsyncNotifier` classes (e.g., `AedDiscoveryNotifier`, `ReportSubmissionNotifier`, `CoverageScenarioNotifier`).
*   **State Invalidation & Side-Effects:** Call `ref.invalidate(...)` on dependent providers after data mutations (e.g., refreshing AED availability after a background sync or updating report submission status).
*   **Async State Handling:** Always handle states via `.when()` or `.maybeWhen()` using consistent components (`DefiLoadingIndicator`, `DefiErrorState`, `DefiEmptyCard`).
*   **Warsaw Bounds Enforcement:** Geolocation and search providers must validate coordinates against Warsaw's administrative bounding box (`GeoBounds.warsaw`). If outside, maintain map center on Warsaw and expose an out-of-bounds state.

---

## 5.1. Naming Rules & Conventions
*   **Providers:** End with `Provider` (e.g., `aedListProvider`, `fastestAedProvider`, `offlinePackagesProvider`).
*   **Services:** End with `Service` (e.g., `GoogleRoutesService`, `OfflineStorageService`, `OtpVerificationService`).
*   **Repositories:** End with `Repository` (e.g., `AedRepository`, `ReportRepository`).
*   **Pages / Sheets:** End with `Page`, `Sheet`, or `Panel` (e.g., `MapPage`, `AedDetailsSheet`, `ReportIssueSheet`, `OfflinePackagesPage`).
*   **Domain Models:** Clear domain nouns matching `PLAN.md` (`Aed`, `AedLocation`, `AedAccessSchedule`, `WalkingRoute`, `ReportDraft`, `OfflinePackage`).
*   **Design System Widgets:** Prefix with `Defi` in `packages/design_system/` (e.g., `DefiButton`, `DefiBottomSheet`, `DefiBadge`, `DefiTextField`, `DefiLoadingIndicator`).
*   **Feature Widgets:** Keep feature-specific widgets inside their feature directory without the `Defi` prefix unless promoted to the shared design system. Feature-internal helpers must use a leading underscore (`_`).

---

## 6. Navigation, City Bounds & Safe Deep Linking (GoRouter)
*   **Route Registration:** Declare all paths as static constants in `RoutePaths` and register in `AppRouter` (`/`, `/aed/:id`, `/report/:id`, `/coverage`, `/offline`).
*   **Warsaw Scope Constraint:** The map is strictly locked to Warsaw. If the device GPS is outside the city bounds:
    *   Do NOT clamp GPS coordinates silently.
    *   Keep the map centered on Warsaw.
    *   Display a prominent banner (`Aplikacja obejmuje Warszawę`) and offer manual origin selection (`Wybierz punkt na mapie`).
*   **Safe Back-Navigation:** Back buttons must check `context.canPop()`. If false (such as when opening a deep link directly to `/aed/:id`), safely fall back to the main map:
    ```dart
    onBack: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RoutePaths.map);
      }
    }
    ```

---

## 7. Bottom Sheets, Panels & Modals
*   **Single-Sheet Rule:** On mobile, only **one** bottom sheet may be active at a time (search start, automatic result, AED details, or report form). Never stack multiple sheets on top of each other.
*   **Sheet States:** Support three distinct heights: compact, medium (~50% height), and expanded. Ensure smooth dragging as well as accessible keyboard/button toggles (`Pokaż szczegóły` / `Zwiń szczegóły`).
*   **Responsive Side Panel:** On wide screens (≥840px), replace the bottom sheet with a 360–420px side panel, maintaining the exact same widget hierarchy and active state.
*   **Confirmation Dialogs:** Always request confirmation for irreversible operations via `DefiConfirmDialog`.

---

## 8. Offline-First, Trust & Robustness
*   **Offline Mode Distinction:**
    *   *Online:* Calculate real walking routes via Google Routes API proxy; display `4 min pieszo · 280 m`.
    *   *Offline:* Fall back to local SQLite data; display straight-line distance `280 m` with an explicit label `Odległość w linii prostej` and a warning `Offline. Dostępność mogła się zmienić`.
*   **Trust & Operational Status:**
    *   Keep opening schedule (`Dostępny według godzin`) strictly separated from physical inspection status (`Sprawdzono AED: [data]`).
    *   Never display "confirmed working" unless verified by physical inspection records.
*   **SMS Verification Isolation:** Phone SMS OTP is strictly restricted to the issue reporting flow (`Zgłoś problem`). Browsing, searching, and routing require **no registration, login, or phone number**.
*   **Draft Preservation:** Form drafts for issue reports must survive network errors and SMS code verification retries without clearing user inputs.
*   **Debug-only APIs:** Avoid referencing debug-only properties like `RenderObject.debugNeedsPaint` directly in production code. Wrap debug helper references inside `assert` blocks:
    ```dart
    bool needsPaint = false;
    assert(() {
      needsPaint = boundary.debugNeedsPaint;
      return true;
    }());
    if (needsPaint) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    ```
