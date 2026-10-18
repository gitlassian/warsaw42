/// Build-time settings: `flutter run --dart-define-from-file=.env` (see .env.example).
abstract final class Env {
  /// Public Mapbox token (pk.*), the same one the web map uses.
  static const mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Supabase project URL and the public publishable (or legacy anon) key.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
}
