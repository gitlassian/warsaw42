# DefiWawa Web

React 19 + TypeScript + Vite SPA. Product rules: `/PLAN.md`, `/DESIGN.md`; architecture rules mirror `frontend/AGENTS.md`.

```sh
npm install
npm run dev      # local dev server
npm run build    # type-check + production build
npm run lint     # oxlint
```

## Structure

```
src/
  main.tsx                      # entry: global styles + RouterProvider
  app/
    routePaths.ts               # RoutePaths: every URL as a constant
    router.tsx                  # appRouter: registers routes
  design-system/                # tokens.css (DESIGN.md tokens), global.css, shared Defi* components
  features/
    <feature>/                  # self-contained, e.g. map, report, coverage
      models/                   # TS types for domain + form/draft state
      services/                 # external APIs (Supabase, Google Routes proxy, geolocation)
      repositories/             # data access combining services
      presentation/
        components/             # dumb components: props in, callbacks out
        pages/                  # *Page: smart containers, routing + state
        sheets/                 # *Sheet / *Panel containers
```

Folders are created when the first file lands in them. Import across folders with `@/` (`@/features/map/...`).
Styling: CSS variables from `design-system/tokens.css` + CSS Modules (`*.module.css`).
