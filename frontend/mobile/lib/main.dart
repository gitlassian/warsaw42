import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:defiwawa/app/app.dart';
import 'package:defiwawa/shared/lib/env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Without the keys the map and the AED list only show load errors.
  assert(
    Env.mapboxToken.isNotEmpty && Env.supabaseUrl.isNotEmpty,
    'No MAPBOX_TOKEN / SUPABASE_URL: run `flutter run --dart-define-from-file=.env` in frontend/mobile.',
  );
  MapboxOptions.setAccessToken(Env.mapboxToken);
  // Polish map labels whatever the phone's language, like the web map's `language: 'pl'`.
  MapboxMapsOptions.setLanguage('pl'); // ignore: experimental_member_use
  runApp(const ProviderScope(child: DefiWawaApp()));
}
