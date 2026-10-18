import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/lib/supabase_client.dart';
import 'package:defiwawa/features/report/models/report.dart';

/// POST /reports (ENDPOINTS.md §4): a direct PostgREST insert with the publishable key.
/// The idempotency key is the report id, so a retry of a stored report fails with 409 and counts as sent.
class ReportService {
  ReportService(this._client);

  final SupabaseClient _client;

  Future<void> submit(String aedId, ReportDraft draft, String idempotencyKey, Duration formTime) async {
    try {
      await _client.restInsert('reports', {
        'id': idempotencyKey,
        'aed_id': aedId,
        'category': draft.category!.apiValue,
        'description': draft.description.trim(),
        'form_ms': formTime.inMilliseconds,
      });
    } on ApiError catch (e) {
      if (e.code != 'http_409') rethrow;
    }
  }
}

final reportServiceProvider = Provider((ref) => ReportService(ref.watch(supabaseClientProvider)));
