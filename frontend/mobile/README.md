# DefiWawa Mobile

Flutter app for iOS and Android. Follow `frontend/AGENTS.md`.

```sh
flutter pub get
flutter run
flutter analyze && flutter test
```

## Structure

```
lib/
  main.dart                     # ProviderScope + DefiWawaApp
  app/
    app.dart                    # MaterialApp.router + AppTheme
    router/                     # RoutePaths, appRouter (GoRouter)
  features/<feature>/           # models/, services/, repositories/, presentation/{widgets,pages,sheets}/
packages/
  design_system/                # AppColors, AppSpacing, AppRadius, AppTheme, Defi* widgets
```

`packages/design_system` is a pub workspace member: one `flutter pub get` at the root resolves everything.
