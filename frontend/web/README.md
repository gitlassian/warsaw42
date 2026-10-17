# DefiWawa Web

React 19 + TypeScript + Vite SPA. Product rules: `/PLAN.md`, `/DESIGN.md`; API contract: `/ENDPOINTS.md`; architecture rules mirror `frontend/AGENTS.md`.

```sh
cp .env.example .env.local   # set VITE_MAPBOX_TOKEN (public pk.* token)
npm install
npm run dev      # local dev server
npm run build    # type-check + production build
npm run lint     # oxlint
npm test         # node --test for pure domain logic (*.test.ts)
```

## Mock data

All services are mocks with the shapes from `ENDPOINTS.md`, marked `shortcut:` in code:

| Service | Mocks | Data |
| --- | --- | --- |
| `features/aeds/services/aedApi.ts` | `GET /aeds`, `/data/status` | `public/mock/aeds.json` — 710 AEDs from the 17.10.2026 Warsaw snapshot (`backend/data/out/aed.json`) |
| `features/discovery/services/routingApi.ts` | `POST /aeds/find`, `/routes/etas`, `/routes/walking` | straight line × 1.3 at 1.3 m/s, L-shaped route geometry |
| `features/coverage/services/coverageApi.ts` | `GET /coverage` | 250 m grid inside the city boundary, computed in the browser |
| `features/report/services/reportApi.ts` | OTP request/resend/verify, `POST /reports` | SMS code is always `123456` |

Swapping a mock for the real API means replacing the function bodies; callers and stores stay the same.

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
    hooks/                      # useMediaQuery, useViewportHeight, useSafeBack
    lib/                        # createStore/useStore, Polish formatters, ApiError, mockLatency
  features/
    aeds/                       # domain: Aed model, hours evaluator, status labels, data store, AED widgets
    discovery/                  # origin (GPS / picked point), find, ETAs, routes; Start/Details/List panels
    map/                        # MapPage shell, Mapbox view, HTML markers, header/menu, camera controller
    coverage/                   # "Zasięg AED" layer: scenarios, threshold, legend, area details
    report/                     # "Zgłoś problem": draft → Kod SMS → confirmation
    offline/                    # web explainer for the mobile offline maps
    dataInfo/                   # data source, freshness, status legend
```

Each feature follows `models/` (types), `services/` (API), `store.ts` (state + actions), `lib/` (pure logic),
`presentation/components/` (dumb components: props in, callbacks out) and `presentation/sheets|pages/` (containers).
Dependencies point one way: `map` → `discovery`/`coverage`/`report` → `aeds` → `shared`/`design-system`.

Layout: below 840 px the map is full screen with one bottom sheet (compact / medium / expanded); from 840 px
the same panel content sits in a 400 px side panel. Import across folders with `@/`.
Styling: CSS variables from `design-system/tokens.css` + CSS Modules (`*.module.css`).
