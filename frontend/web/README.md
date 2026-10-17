# DefiWawa Web

React 19 + TypeScript + Vite SPA. Product rules: `/PLAN.md`, `/DESIGN.md`; API contract: `/ENDPOINTS.md`; architecture rules mirror `frontend/AGENTS.md`.

```sh
cp .env.example .env.local   # set VITE_MAPBOX_TOKEN, VITE_SUPABASE_URL, VITE_SUPABASE_PUBLISHABLE_KEY
npm install
npm run dev      # local dev server
npm run build    # type-check + production build
npm run lint     # oxlint
npm test         # node --test for pure domain logic (*.test.ts)
```

## Data

`shared/lib/supabase.ts` calls the Supabase project with the publishable key (`fetch`, no SDK). Without
`VITE_SUPABASE_URL`/`VITE_SUPABASE_PUBLISHABLE_KEY` the AED list falls back to the 17.10.2026 snapshot in
`public/mock/aeds.json`; finding and routing always need the Edge Functions.

| Service | Source |
| --- | --- |
| `features/aeds/services/aedApi.ts` | table `aeds` (active rows, mapped by `lib/fromRow.ts`, photos from Storage) and `app_data` key `status` via PostgREST |
| `features/discovery/services/routingApi.ts` | Edge Functions `aeds-find`, `routes-etas`, `routes-walking` (Mapbox walking routes) |
| `features/report/services/reportApi.ts` | insert into `reports` via PostgREST (simulated without Supabase settings) |

The Edge Functions answer CORS only for origins listed in their `ALLOWED_ORIGINS` secret
(`supabase secrets set ALLOWED_ORIGINS=... --project-ref <ref>`); add every dev and deployed web origin.

Still mocks, marked `shortcut:` in code (callers and stores stay the same when they are replaced):

| Service | Mocks | Why |
| --- | --- | --- |
| `features/coverage/services/coverageApi.ts` | `GET /coverage` | circles of the threshold radius around the eligible AEDs, merged into white covered areas and red gaps in the browser (`polygon-clipping`) |

## Structure

```
src/
  main.tsx                      # entry: fonts, Mapbox CSS, global styles, RouterProvider
  assets/brand/                 # logo: [D]efiWawa lockup + symbol; favicon, app icons, manifest live in public/
  app/
    routePaths.ts               # RoutePaths + buildPath helpers
    router.tsx                  # MapPage shell; child routes render into the sheet/panel
  design-system/                # tokens.css, global.css, tone, shared components:
    components/                 # AppIcon, Text, Stack, Button/ButtonLink, IconButton, Badge,
                                # Notice, TextField, ChoiceGroup, Disclosure, PanelHeader, Sheet, Spinner
  shared/
    geo/                        # Warsaw boundary (OSM), bounds, distance, isInsideWarsaw
    hooks/                      # useMediaQuery, useViewportHeight
    lib/                        # createStore/useStore, Polish formatters, ApiError, mockLatency
  features/
    aeds/                       # domain: Aed model, hours evaluator, status labels, data store, AED widgets
    discovery/                  # origin (GPS / picked point), find, ETAs, routes; Start/Details/List panels
    map/                        # MapPage shell, Mapbox view, HTML markers, header/menu, camera controller
    coverage/                   # "Odległość do najbliższego AED" layer: scenarios, threshold, legend, area details
    report/                     # "Zgłoś problem": draft → confirmation
    dataInfo/                   # data source, freshness, status legend
```

Each feature follows `models/` (types), `services/` (API), `store.ts` (state + actions), `lib/` (pure logic),
`presentation/components/` (dumb components: props in, callbacks out) and `presentation/sheets|pages/` (containers).
Dependencies point one way: `map` → `discovery`/`coverage`/`report` → `aeds` → `shared`/`design-system`.

Layout: below 840 px the map is full screen with one bottom sheet (compact / medium / expanded); from 840 px
the same panel content sits in a 400 px side panel. Import across folders with `@/`.
Styling: CSS variables from `design-system/tokens.css` + CSS Modules (`*.module.css`).

## Languages

Polish is the default; English lives under `/en/...` (for example `/en/aed/12`, `/en/coverage`). The router gets
`basename: '/en'` on those URLs, so routes and links inside the app are identical and a language change is a full page
load (the `PL`/`EN` pill in the header). Hosting must serve `index.html` for `/en/*` like for every other deep link.

Texts are written in Polish and passed through `t('Polski tekst {n}', { n })` from `@/i18n`; the English version is looked
up by the exact Polish text in `src/i18n/en.*.ts`. Without an entry the Polish text shows. `npm test` fails when a `t(...)`
literal has no English entry or loses a `{placeholder}`. Modules imported by node tests import `t` with the relative
`.ts` path. Data from the database (venue names, addresses, source hours wording) is not translated.
