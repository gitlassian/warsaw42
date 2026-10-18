# DefiWawa Mobile

Flutter app for iOS and Android: the phone layout of the web app (`frontend/web`) one to one. Follow `AGENTS.md`.

```sh
cp .env.example .env          # MAPBOX_TOKEN, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY (the web's public values)
flutter pub get
flutter run --dart-define-from-file=.env
flutter analyze && flutter test
```

The Mapbox token must not be restricted to web URLs, or the native map cannot load. The Edge Functions need
no `ALLOWED_ORIGINS` entry for the app: native requests send no `Origin`.

## Structure

```
lib/
  main.dart                     # Mapbox token, ProviderScope + DefiWawaApp
  app/
    app.dart                    # MaterialApp.router + AppTheme
    router/                     # RoutePaths, RouteHandle (sheet height, close, back target), appRouter
  shared/
    geo/                        # Warsaw boundary (OSM), bounds, distance, isInsideWarsaw
    lib/                        # Env, Supabase client (REST, Storage, Edge Functions), Polish/Warsaw-time formats
  features/<feature>/           # models/, lib/ (pure logic), services/, providers/, presentation/{widgets,pages,sheets}/
    aeds/                       # Aed model, hours evaluator, status labels, AED data, AED widgets
    discovery/                  # origin (GPS / picked point / address), find, ETAs, routes; start, details, list panels
    map/                        # MapPage shell, Mapbox view and layers, marker bitmaps, header and map controls
    navigation/                 # turn-by-turn progress, direction banner, navigation panel
    coverage/                   # "Odległość do najbliższego AED": scenarios, radius, legend (Clipper2 in an isolate)
    placement/                  # "Gdzie dodać AED": ranked new sites / AEDs to open 24/7 per half hour (app_data.placement)
    report/                     # "Zgłoś problem": draft → confirmation
packages/
  design_system/                # AppColors, AppSpacing, AppRadius, AppTheme, Noto Sans, Phosphor SVGs, Defi* widgets
```

`packages/design_system` is a pub workspace member: one `flutter pub get` at the root resolves everything.

Differences from the web, on purpose: no "O danych" panel (web phones have no button for it either; the data
date and source stay in the AED card), no wide (≥840) side-panel layout, no mock AED snapshot (the app needs Supabase),
no form honeypot. Map markers are Mapbox symbol layers drawn from the same fonts and icons as the web's HTML
markers; cluster counts use Open Sans, which Mapbox hosts (it has no Noto Sans). Android back goes to the
parent screen (navigation → AED card → map).
