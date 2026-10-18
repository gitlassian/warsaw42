import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:defiwawa/shared/lib/env.dart';

/// Stable error code from the API (ENDPOINTS.md §11); the UI localizes the code, not the message.
class ApiError implements Exception {
  const ApiError(this.code);

  final String code;

  @override
  String toString() => 'ApiError($code)';
}

/// Supabase REST, Storage and Edge Functions access without an SDK.
class SupabaseClient {
  SupabaseClient({String url = Env.supabaseUrl, String key = Env.supabaseKey, http.Client? client})
    : _url = url.replaceAll(RegExp(r'/+$'), ''),
      _key = key,
      _http = client ?? http.Client();

  final String _url;
  final String _key;
  final http.Client _http;

  // Legacy anon keys are JWTs and go in both headers; publishable keys (sb_publishable_…) only in `apikey`.
  Map<String, String> get _headers =>
      _key.startsWith('eyJ') ? {'apikey': _key, 'Authorization': 'Bearer $_key'} : {'apikey': _key};

  /// GET `/rest/v1/<path>` (PostgREST). Row-level security limits anon to active AEDs and `app_data`.
  Future<Object?> restGet(String path) async {
    final response = await _http.get(Uri.parse('$_url/rest/v1/$path'), headers: _headers);
    if (response.statusCode >= 300) throw Exception('supabase ${path.split('?').first} ${response.statusCode}');
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// POST `/rest/v1/<table>` with `return=minimal`, for tables anon may insert into but not read.
  /// Rate limits raised in the database (PT429) arrive as 429 and become `rate_limited`.
  Future<void> restInsert(String table, Object row) async {
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_url/rest/v1/$table'),
        headers: {..._headers, 'Content-Type': 'application/json', 'Prefer': 'return=minimal'},
        body: jsonEncode(row),
      );
    } catch (_) {
      throw const ApiError('network');
    }
    if (response.statusCode == 429) throw const ApiError('rate_limited');
    if (response.statusCode >= 300) throw ApiError('http_${response.statusCode}');
  }

  String storagePublicUrl(String bucket, String file) => '$_url/storage/v1/object/public/$bucket/$file';

  /// POST `/functions/v1/<name>`. Routing functions answer `{ data, meta }`, failures `{ error: { code } }`.
  Future<Map<String, dynamic>> callFunction(String name, Object body) async {
    final response = await _http.post(
      Uri.parse('$_url/functions/v1/$name'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {}
    if (response.statusCode >= 300) {
      final error = (json is Map) ? json['error'] : null;
      final code = (error is Map) ? error['code'] : null;
      throw ApiError(code is String ? code : 'http_${response.statusCode}');
    }
    return json as Map<String, dynamic>;
  }
}

final supabaseClientProvider = Provider((ref) => SupabaseClient());
