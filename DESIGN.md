# DefiWawa: Unified Design System

Status: implementation baseline. Date: 17 October 2026.

Applies to Flutter web, Android, and iOS. Product and data requirements are defined in [PLAN.md](PLAN.md) and [ENDPOINTS.md](ENDPOINTS.md). The reference selection is explained in [DESIGN_RESEARCH.md](DESIGN_RESEARCH.md).

In the implementation, tokens and shared components live in `packages/design_system/`. Screens consume them through a shared theme; platform default colors must not override the app palette.

## 1. Direction

**A calm, clear AED map with a green accent, large text, and one primary action.**

People should quickly understand where to go, how long it will take, and how to access the device. Open directly to the map. Browsing, searching, and routing require no registration.

Use Google Maps as the reference for the map and details panel structure. Use Citymapper for prominent travel times and the priority of the current action. Use Uber for restrained styling and consistent controls. All decisions follow the shared system below.

Principles:

- Show travel time, access, and entrance instructions first. Reveal additional information on request.
- Provide one primary action at each stage. Give secondary actions less visual emphasis.
- Combine color, an icon, and a short label to explain each state.
- Use the same components and values across sections and platforms.
- Prioritize readability over decorative effects and fixed container heights.
- Keep emoji, decorative labels, and technical jargon out of the interface.

## 2. Color

Primary accent: **`#237A57`**, a calm, rich green. Use it for the primary action, active selection, and route line. Light green shades provide backgrounds; darker shades maintain readability.

The first release uses one light theme throughout, including app dialogs. Online and offline providers may use different basemap colors; our panels, markers, and controls retain their shared tokens.

| Token | Value | Purpose |
| --- | --- | --- |
| `color.accent` | `#237A57` | Primary action, active selection, route line |
| `color.accent.hover` | `#1D6B4B` | Primary action hover |
| `color.accent.pressed` | `#185A40` | Primary action pressed state |
| `color.accent.soft` | `#EAF5EE` | Selected item and access status backgrounds |
| `color.background` | `#F5F8F6` | Screen backgrounds and secondary areas |
| `color.surface` | `#FFFFFF` | Panels, fields, cards, primary button text |
| `color.text` | `#17231D` | Primary text |
| `color.text.secondary` | `#506158` | Addresses, explanations, secondary actions |
| `color.text.muted` | `#5D6E63` | Dates, captions, disabled control text |
| `color.border` | `#D8E2DC` | Decorative dividers |
| `color.border.control` | `#75857B` | Fields and controls that need a distinguishable outline |
| `color.focus` | `#125A3C` | Visible keyboard focus |
| `color.warning` | `#8A570A` | Access restrictions and warnings |
| `color.warning.soft` | `#FFF5DF` | Warning background |
| `color.danger` | `#B23B36` | Confirmed unavailability and errors |
| `color.danger.soft` | `#FCEDEC` | Error background |
| `color.unknown` | `#56645B` | Unknown hours and unconfirmed information |
| `color.unknown.soft` | `#EEF2EF` | Unknown state background |
| `color.location` | `#2869B1` | User location and accuracy only |
| `color.disabled` | `#EDF1EE` | Disabled button background |

Usage rules:

- A green button indicates an action; a green status indicates access according to known hours. Shape, icon, and label distinguish their meanings.
- Reserve red and amber for their semantic states. Selecting a point does not change its status.
- Place regular text on opaque surfaces. Labels over the map have their own white background.
- Do not use gradients, glows, glass panels, or decorative colored blocks. The one exception: soft dark gradient scrims (`color.text` at about 30–45% fading to transparent) behind controls that sit on the map, so they stay readable, and a slight 24-wide shadow (20%) from the desktop side panel onto the map.

Calculated contrast for the main pairs:

| Pair | Contrast |
| --- | --- |
| White text / primary green | `5.26:1` |
| Primary text / white background | `16.22:1` |
| Secondary text / white background | `6.58:1` |
| Green text / light green background | `4.71:1` |
| Error text / error background | `5.17:1` |
| Warning text / warning background | `5.62:1` |
| Control outline / white background | `3.89:1` |

These calculations validate the tokens. Check actual states, overlays, and map content again in the implemented interface.

## 3. Copy and Typography

**One font: Noto Sans.** Bundle local font assets so they are available on an offline cold start. Use weight 400 for body text, 600 for labels and headings, and 700 for travel times and important numbers.

Sizes below use Flutter logical units at the default text scale.

| Role | Size / line height | Weight |
| --- | --- | --- |
| Travel time in the selected result | `32 / 40` | 700 |
| Screen title | `24 / 32` | 600 |
| AED or venue name | `20 / 28` | 600 |
| Section heading | `18 / 26` | 600 |
| Body text, address, entrance instructions | `16 / 24` | 400 |
| Button, list item, input | `16 / 24` | 600 for actions, 400 for input text |
| Metadata and map travel time label | `14 / 20` | 400 or 600 |

Readability rules:

- Keep travel times, access conditions, errors, and entrance instructions at 16 or larger. Use 14 for brief metadata and marker labels.
- Support system text scaling without an artificial scale cap. Rows, buttons, and panels grow with their content.
- Do not truncate critical labels with an ellipsis. Allow wrapping when needed.
- Use tabular figures from the same font for times and distances.
- Left-align text. Button labels and short marker values may be centered.
- Use sentence case. Avoid letter spacing, all caps, and italics for important messages.
- Limit explanatory lines in wide panels to roughly 60 characters.

### Interface Language

The primary interface language is Polish. The English prose in this document provides design instructions; Polish examples are the intended interface copy. Store all user-facing strings in localization resources and use one selected language per screen. Preserve original venue names and addresses.

Use short, concrete wording. Each message answers one question. Show an explanation where it helps the user act. Place long original access descriptions in an expandable section labeled "Informacje ze źródła".

| Meaning | Interface label |
| --- | --- |
| Primary action | `Znajdź najbliższy defibrylator` |
| Time and distance | `4 min pieszo · 280 m` |
| Automatic selection result | `Najszybszy z porównanych` |
| Access according to listed hours | `Dostępny według godzin` |
| Around-the-clock access established by the schedule | `Dostęp całodobowy` |
| Closing time | `Dostęp do 18:00` |
| No information on hours or access | `Niedostępny` with `Brak informacji o godzinach` / `Brak informacji o dostępie` |
| Closed venue | `Teraz zamknięty` |
| Unclear access conditions | `Dostęp niepotwierdzony` |
| Confirmed unavailability | `AED niedostępny` |
| Entrance instructions | Heading `Wejście`, followed by actual source information |
| Manual origin selection | `Wybierz punkt na mapie` |
| Alternatives | `Inne defibrylatory` |
| Issue reporting | `Zgłoś problem` |
| Offline map | `Mapa offline` |
| Coverage | `Odległość do najbliższego AED` |

Keep `API`, `PostGIS`, `timestamp`, "AI", and internal status names out of user-facing labels.

## 4. Icons

**One family: Phosphor Icons, bold weight** (`@phosphor-icons/core` on web, `phosphor_flutter` on mobile). Toggle controls show their switched-on state with the filled glyph. The Flutter app still uses Material Symbols until it is migrated.

- Default size: 24 × 24. Supporting inline icons: 20 × 20. AED icon inside a large marker: 32 × 32.
- Every icon button has a hit area of at least 48 × 48.
- Indicate selection through background and outline; a switched-on map control also swaps to the filled glyph.
- Icons inherit the color of their text or semantic state. Do not use multicolored decorative icons.
- Primary and unfamiliar actions have visible text labels. Round map controls are 56 × 56 tiles with a short caption under the icon (`Info`, `Pozycja`, `Zasięg`, `Pora`, `Filtry`). Close controls and the mobile header info button may be icon-only, with accessible names and web tooltips.
- Hide decorative icons next to labels from screen readers to avoid repeating the text.
- Do not substitute emoji or Unicode symbols for icons.

| Meaning | Phosphor icon |
| --- | --- |
| AED | `heartbeat` (echoes the logo's pulse) |
| User location | `gps-fix` |
| Address or selected point | `map-pin` |
| Walking | `person-simple-walk` |
| Route | `path` |
| Access hours, map time | `clock` |
| Known access | `check-circle` |
| Closed or unavailable | `lock-simple` |
| Unknown | `question` |
| Warning | `warning` |
| Device unavailable or error | `warning-circle` |
| Coverage layer | `circles-three` |
| Filters | `funnel-simple` |
| Information | `info` |
| Report an issue | `flag` |
| AED list | `list-bullets` |
| Close, expand | `x`, `caret-down` |
| Navigation maneuvers | `arrow-up`, `arrow-bend-up-left/right`, `arrow-up-left/right`, `arrow-u-down-left/right`, `arrow-clockwise`/`arrow-counter-clockwise`, `flag-checkered` |

One shared `AppIcon` component uses local assets from the chosen family on web and mobile. Bundle icons with the app so they work offline. Do not mix them with built-in Material Icons, SF Symbols, or another library. Preserve map provider attribution in its required form.

## 5. Spacing, Shape, and Depth

| Property | Value |
| --- | --- |
| Spacing scale | `4, 8, 12, 16, 24, 32, 48` |
| Narrow screen and panel padding | 16 |
| Wide panel padding | 24 |
| Icon-to-label gap | 8 |
| Gap between related rows | 8 |
| Gap between groups inside a panel | 24 |
| Button, input, and standard card radius | 12 |
| Bottom sheet top corner radius | 24 |
| Short map label and round map control | Fully rounded |
| Primary button minimum height | 56 |
| Input and secondary button minimum height | 48 |
| Selection row minimum height | 64, growing with content |

Panels are opaque. Separate regular text groups with spacing and list rows with a thin divider. Use nested cards only for a distinct choice or message.

Shadows separate controls from the map: panel `0 4 24`, color `#17231D` at 12% opacity; floating button `0 2 8`, the same color at 10% opacity. Regular rows inside a panel have no shadow.

## 6. Layout and Navigation

### Narrow Screens: Below 840

- The map fills the available screen. Place a compact DefiWawa name and access to secondary features at the top.
- Use one bottom sheet for the search start, result, list, or selected AED details. Do not stack sheets on top of one another.
- One map time: the clock control previews availability at another weekday and hour for markers, the list, filters and coverage. While previewing, a warning banner `Podgląd: <dzień>, <godzina>` with `Wróć do teraz` stays on the map, also after the picker closes. Finding the nearest AED always returns the map to now, because the server searches by the real clock.
- "Znajdź najbliższy defibrylator" is pinned on every screen, outside sheets and panels: a white bar on the bottom edge that an open sheet covers (from 840: a floating button at the bottom right of the map). The start screen has no sheet; from 840 the map fills the window and the header floats top-left. Offer manual origin selection only when location is denied or unavailable. Panels have no back button; the DefiWawa logo returns to the start. Panels for the selected AED (details, report) have a close button that clears the selection and its route: in the sheet's top-right corner on narrow screens, in the header row next to the logo from 840. The coverage and `O danych` panels get the same close button on every screen size (it does not clear a route). The close icon lines up with the panel content edge; its hit area extends past it.
- The result sheet shows travel time, address, access, and entrance instructions. Expand additional details below.
- Provide compact, medium, and expanded sheet states. At the default text scale, medium occupies about 70% of the available height; content and text scale determine its actual height.
- Support a button and keyboard interaction as well as dragging to expand the sheet. Accessible button names: `Pokaż szczegóły` / `Zwiń szczegóły`.
- Long content scrolls after expansion; controls must not obscure the final row.
- With large text or a short landscape viewport, details may occupy the full screen. Keep the map accessible through the logo link.

### Wide Screens: 840 and Above

- Place a 360–420-wide panel on the left and the map in the remaining space on the right.
- The header holds only the logo; the info button (`O danych`) tops the round map controls, which stack right above the find card at the bottom right; their pop-ups open to the left and grow up. The web app has no offline section; offline maps are mobile-only.
- The panel uses the same information, actions, and order as the mobile version.
- Available logical width determines when a zoomed interface switches to the narrow layout.
- Do not add a separate bottom sheet over the side panel.

Shared rules:

- Keep the primary action in a stable area of the panel. Change its label only when the task changes.
- Make `Odległość do najbliższego AED` (coverage), nearby AEDs, data information, and mobile downloads available through a menu with text labels. Coverage is also accessible through the map layers control.
- On web, "Mapa offline" explains the mobile capability; offer downloads in the mobile app.
- Put address search inside the origin selection flow. Keep the initial screen focused on automatic AED discovery.
- Restrict map bounds and selectable origins to Warsaw, online and offline, as specified in PLAN.md.
- Position map controls around the current sheet height, safe areas, keyboard, and map attribution.

## 7. Components

### Buttons and Inputs

Primary button: green background, white 16/24 text at weight 600, radius 12, minimum height 56. An icon is optional; the label is always visible. Use one primary button for the current task.

Secondary button: white background, `color.accent` text, distinguishable `color.border.control` outline, minimum height 48. Link actions use the same text color and an underline, with a hit area of at least 48.

Use the defined hover and pressed tokens. Focus: a 2-wide outer `color.focus` outline with a 2-wide white gap. Disabled buttons use `color.disabled` backgrounds and `color.text.muted` text; explain why the action is unavailable nearby.

During an operation, preserve the button's size and show a short status label with a compact progress indicator. Keep the label readable. Repeated presses must not start duplicate operations.

Inputs have a visible label above the field, a white background, and a `color.border.control` outline. A placeholder does not replace the label. Place an error below its field and explain what to correct. Issue descriptions use a multiline field. Buttons grow taller when labels wrap under text scaling.

### AED Markers and Travel Times

- Default marker: white surface, recognizable location marker shape, `heartbeat` icon, and readable `AED` label. Start with a 48 × 48 hit area; grow with the text if the label is inside the marker.
- Outline color and a small status icon communicate access: green check, gray lock, gray question mark, or red warning. Explain the exact meaning in the label and list.
- Give the selected marker an additional 3-wide outer `color.accent` outline with a white separator. Preserve its underlying status, including a red warning.
- Each individually displayed nearby AED has a small white travel time label, such as `4 min`, using 14/20 text at weight 600. Let the label grow with text scaling.
- While calculating time, use a static neutral placeholder. On failure, show `—` and explain `Nie udało się obliczyć czasu` in the details card.
- Do not show minutes without a selected origin. Offline, show distance such as `280 m`, with an explicit `Odległość w linii prostej` label above the results.
- At overview zoom levels, group points into numbered clusters. Resolve overlapping labels through clustering and the list rather than smaller type. Below zoom 15 a cluster shows the AED count; a cluster with at least one AED available now uses `color.accent` and the soft green background. Tapping a cluster zooms in until it splits. The selected AED is never hidden inside a cluster.
- The accessible name includes AED, venue, access, and travel time or distance. Announce the meaning of `—` in words.

### Selected AED Card

Content order:

1. Prominent walking time, with distance alongside in regular text. Offline, emphasize straight-line distance instead.
2. Venue name and full address.
3. Short access status and the next known change in hours, as colored text without a chip, after a clock icon in the same color (e.g. `Dostępny do 18:00` in `color.accent`).
4. `Wejście`: actual entrance instructions, spanning multiple lines when needed.
5. Route action and access to alternatives.
6. Expandable hours, device information, source, and dates.
7. `Zgłoś problem` as a secondary action.

Mockup content example; all values are illustrative:

```text
4 min pieszo · 280 m
[Nazwa obiektu]
[Pełny adres]
Dostępny według godzin
Dostęp do 18:00
Wejście
[Instrukcja wejścia z danych źródłowych]
```

When automatic discovery has already calculated a route, display it immediately. `Pokaż trasę` fits the camera to the route; it does not simulate starting turn-by-turn navigation. For a manually selected AED without a calculated route, use `Wyznacz trasę`.

### Nearby AED List

Each row contains travel time or distance, name, address, and access status. Selecting the row selects its marker and card. Indicate the current selection with an outline, soft green background, and an accessible selected state.

The list is a complete way to find an AED without operating the map. Label closed and unknown options explicitly, keeping them separate from automatically selected eligible results.

### Route and Location

Route: a 5-wide green line over a white casing with a total width of 9. The casing separates it from parks, roads, and coverage areas. Give the origin and destination different icons and accessible names.

User location: a blue dot with a white border and a soft pulsing halo. The translucent accuracy area appears for a moment after each GPS fix, then fades out; it is hidden during navigation, where the user is a direction arrow. Indicate a manually selected origin with a marker rather than a GPS dot.

The first release shows route geometry, time, distance, and our own entrance instructions. Do not depict turn-by-turn instructions or offline routing as available features in mockups.

## 8. States and Trust

Display access and device condition separately. A green schedule-based status does not confirm that an AED works. Verified device condition requires separate evidence and a date. An unreviewed user report does not change the public status.

For automatic results, evaluate access at the expected arrival time under the conditions in PLAN.md. During browsing, show access at the selected time. No information on hours or access means unavailable: such AEDs show as `Niedostępny`, never as available.

| Situation | Message and available action |
| --- | --- |
| Search in progress | `Szukamy defibrylatora…`; keep the map visible and allow cancellation |
| Location unavailable or permission denied | `Nie możemy ustalić Twojej lokalizacji.`; `Wybierz punkt na mapie` |
| GPS outside the city | `Aplikacja obejmuje Warszawę.`; allow an origin inside the city without substituting the GPS position |
| No eligible AED | `Nie znaleźliśmy AED dostępnego według danych.`; show unknown-access alternatives separately when available |
| Route calculation failed | `Nie udało się wyznaczyć trasy.`; retry or view straight-line distances |
| Basemap failed to load | `Nie udało się wczytać mapy.`; retry and continue through the AED list |
| Offline with a downloaded package | `Offline. Dostępność mogła się zmienić.`; show the data date and straight-line distances |
| Offline without a package | `Brak pobranej mapy.`; show only genuinely saved information, if any |
| Stale data | No warning; the last synchronization date is shown in `O danych` |
| Entrance instructions missing | `Brak informacji o wejściu.` |
| Request rate limited | Briefly explain the wait and allow retrying at the time provided by the server |

Show errors and restrictions inside the relevant panel. Important messages persist until resolved or explicitly dismissed. Use brief toast notifications only for reversible secondary actions.

Label dataset downloads `Dane pobrano: [data, godzina]`. When known, label physical device inspections separately as `Sprawdzono AED: [data]`. Do not present synchronization time as a device inspection.

Localize dates and numbers for Polish and display time in Europe/Warsaw. Example formats: `17.10.2026, 14:30`, `08:00–18:00`, `280 m`, `1,2 km`. Use meters and kilometers throughout the interface.

## 9. Issue Reporting

Open the form from the AED card and retain its connection to the selected device. Title: `Zgłoś problem`.

The form has one screen with category and description; no phone number or SMS code. Use short Polish category names: `Brak AED`, `Problem z urządzeniem`, `Brak dostępu`, `Błędne godziny`, `Błędna lokalizacja`, `Inny problem`.

`Wyślij zgłoszenie` submits the report. Preserve the draft on errors and back navigation. When the rate limit is reached: `Wysłano zbyt wiele zgłoszeń. Spróbuj ponownie później.`

Success: `Dziękujemy. Zgłoszenie czeka na sprawdzenie.` Allow an immediate return to the selected AED. Offline, a report can be saved as a draft; submission requires a connection. Do not introduce app login or a profile for this flow.

## 10. Mobile Downloads

The `Mapa offline` screen lists Warsaw and supported districts. Each package shows its name, size, date, status, and one available action: `Pobierz`, `Anuluj`, `Aktualizuj`, or `Usuń`.

Downloads show actual progress and data volume. If the total size is unknown, show an honest loading state without inventing a percentage. Storage and connection errors explain the next step.

Keep the existing package usable during updates and after update failures. Show basemap and AED data dates separately when they differ. Outside a downloaded area, show `Poza pobranym obszarem`; keep saved AED details accessible.

## 11. AED Coverage

Open `Odległość do najbliższego AED` as a separate layer mode; its sheet opens at the same medium height as AED details. Retain the map and the shared control styling.

Provide `Wszystkie publiczne`, `Dostępne o tej porze`, and `Całodobowe` scenarios. The second one uses the map time, shown as `Pora: teraz` (or the previewed time) with `Zmień` opening the same time picker as the clock control. Label the threshold setting `Promień`, initially 500 m as specified in PLAN.md.

Show gaps with a translucent red fill and hatching; AEDs without information do not cover any area. The legend sits right under the title (`Do 500 m od AED`, `Dalej niż 500 m`) and replaces any separate description. Routes and AEDs remain distinguishable over the layer.

Selecting an area shows the distance to the nearest eligible AED and a link to it. One footnote covers the limits: `Odległość w linii prostej. Dane mogą być niepełne.` Do not repeat the scenario, time or data date already shown, and do not label these areas as definitively dangerous or as proof that no devices exist.

While calculating, show `Obliczamy zasięg…`. If a saved layer remains visible until a new one is ready, explicitly label it with its own time and scenario.

## 12. Motion and Accessibility

- Button feedback and selection changes: 120–160 ms. Panel transitions: 200–250 ms. Transitions must not delay access to results.
- Move the map only at the user's request or after an explicit result selection. New data must not independently change the zoom or selected AED.
- Avoid continuous marker pulses, flashing, bouncing, and decorative animations.
- With reduced motion enabled, use instant transitions or brief opacity changes. Provide loading information as text.
- Regular text has a minimum contrast of 4.5:1. Meaningful icons, outlines, and indicators have at least 3:1 contrast against adjacent backgrounds. Primary text uses higher contrast.
- All functions are keyboard accessible. Keep focus visible and clear of sticky panels. Closing a dialog restores focus to its trigger.
- Screen readers receive action names, the selected result, and meaningful state changes. Do not continuously announce every minute update across all markers.
- Meaning must not depend solely on color, gestures, map position, or hover.
- Check text at 200% scaling, layouts from 320 logical units, web zoom up to 400%, the onscreen keyboard, and landscape orientation. The map does not replace an accessible list.

## 13. Design and Implementation Readiness

- [ ] Use one palette, Noto Sans, and Phosphor Icons (bold); no emoji.
- [ ] Make the primary action visible without introductory screens; offer manual origin selection when location is unknown.
- [ ] Make travel time, access, and entrance instructions readable without opening additional sections when the data is known.
- [ ] Support text scaling without losing actions or truncating critical information.
- [ ] Keep default, selected, pressed, loading, error, and disabled states consistent.
- [ ] Make every AED accessible through the list; avoid unreadable overlaps between markers and labels.
- [ ] Separate scheduled access from device condition and inspection status.
- [ ] Clearly distinguish offline straight-line distances from online walking times.
- [ ] Cover closed AEDs, unknown hours, location denial, offline use, and routing failures.
- [ ] Let anyone submit a report without login or verification; preserve drafts on errors.
- [ ] Show coverage scenario, threshold, and data limitations; provide downloads on mobile.
- [ ] Use the same components on web and mobile at equivalent available widths.
- [ ] Check contrast, keyboard access, screen readers, large text, safe areas, and map attribution.

## Sources

This is DefiWawa's own design system. References inform the principles; the colors, sizes, and priorities in this document are chosen for this project.

- [Google Maps: independent DESIGN.md](https://github.com/Meliwat/awesome-ios-design-md/blob/main/design-md/travel/google-maps/DESIGN.md).
- [Citymapper: independent DESIGN.md](https://github.com/Meliwat/awesome-ios-design-md/blob/main/design-md/travel/citymapper/DESIGN.md).
- [Uber: independent DESIGN.md](https://github.com/Meliwat/awesome-ios-design-md/blob/main/design-md/travel/uber/DESIGN.md).
- [Noto Sans](https://fonts.google.com/noto/specimen/Noto+Sans).
- [Phosphor Icons](https://phosphoricons.com).
- [W3C: text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) and [non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).
