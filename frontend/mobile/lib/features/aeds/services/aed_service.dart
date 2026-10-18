import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/lib/supabase_client.dart';
import 'package:defiwawa/features/aeds/lib/from_row.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';

/// AEDs and the data status from the database (`aeds`, `app_data.status`).
class AedService {
  AedService(this._client);

  final SupabaseClient _client;
  Future<List<Aed>>? _aeds;

  /// One request per app run; a failed one is retried on the next call.
  Future<List<Aed>> fetchAeds() => _aeds ??= _fetchAeds();

  Future<List<Aed>> _fetchAeds() async {
    try {
      // shortcut: one request; PostgREST caps a response at 1000 rows by default (897 on 17.10.2026), paginate before that.
      final rows = await _client.restGet('aeds?active=eq.true&select=$aedColumns&order=source_id') as List;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          aedFromRow(row, (file) => _client.storagePublicUrl('aed-photos', file)),
      ];
    } catch (_) {
      _aeds = null;
      rethrow;
    }
  }

  Future<DataStatus> fetchDataStatus() async {
    final rows = await _client.restGet('app_data?key=eq.status&select=data') as List;
    if (rows.isEmpty) throw StateError('app_data status missing');
    final data = (rows.first as Map)['data'] as Map;
    return DataStatus(
      fetchedAt: DateTime.parse(data['updated_at'] as String),
      aedCount: (data['aed_count'] as num).toInt(),
      attribution: data['attribution'] as String,
    );
  }
}

final aedServiceProvider = Provider((ref) => AedService(ref.watch(supabaseClientProvider)));
