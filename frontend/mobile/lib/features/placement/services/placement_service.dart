import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/lib/supabase_client.dart';
import 'package:defiwawa/features/placement/models/placement.dart';

/// `app_data.placement` from the database (written by backend/pipeline/placement.py through the seed).
class PlacementService {
  PlacementService(this._client);

  final SupabaseClient _client;

  Future<PlacementData> fetchPlacement() async {
    final rows = await _client.restGet('app_data?key=eq.placement&select=data') as List;
    if (rows.isEmpty) throw StateError('app_data placement missing');
    return PlacementData.fromJson((rows.first as Map)['data'] as Map<String, dynamic>);
  }
}

final placementServiceProvider = Provider((ref) => PlacementService(ref.watch(supabaseClientProvider)));
