import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/lib/supabase_client.dart';
import 'package:defiwawa/features/report/models/report.dart';
import 'package:defiwawa/features/report/services/report_service.dart';

/// Random UUID v4 for the idempotency key.
String _uuid() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

enum ReportStep { form, done }

/// Per-AED report flow. Kept in memory only: the draft survives errors and back navigation.
class ReportFlow {
  ReportFlow({
    this.draft = const ReportDraft(),
    this.step = ReportStep.form,
    this.busy = false,
    this.error,
    String? idempotencyKey,
    DateTime? openedAt,
  }) : idempotencyKey = idempotencyKey ?? _uuid(),
       openedAt = openedAt ?? DateTime.now();

  final ReportDraft draft;
  final ReportStep step;
  final bool busy;

  /// Stable error code, localized by the panel.
  final String? error;

  /// One key per draft, so a retried submission cannot create a duplicate.
  final String idempotencyKey;

  /// When the form was first opened; the elapsed time is sent as a spam signal.
  final DateTime openedAt;

  ReportFlow copyWith({ReportDraft? draft, ReportStep? step, bool? busy, String? error}) => ReportFlow(
    draft: draft ?? this.draft,
    step: step ?? this.step,
    busy: busy ?? this.busy,
    error: error,
    idempotencyKey: idempotencyKey,
    openedAt: openedAt,
  );
}

class ReportNotifier extends Notifier<Map<String, ReportFlow>> {
  @override
  Map<String, ReportFlow> build() => const {};

  ReportFlow flow(String aedId) => state[aedId] ?? ReportFlow();

  void _update(String aedId, ReportFlow flow) => state = {...state, aedId: flow};

  /// Starts timing the form; keeps an existing draft.
  void open(String aedId) {
    if (!state.containsKey(aedId)) _update(aedId, ReportFlow());
  }

  void updateDraft(String aedId, {ReportCategory? category, String? description}) {
    final current = flow(aedId);
    _update(
      aedId,
      current.copyWith(
        draft: ReportDraft(
          category: category ?? current.draft.category,
          description: description ?? current.draft.description,
        ),
      ),
    );
  }

  /// "Wyślij zgłoszenie". The caller validates the draft first.
  Future<void> submit(String aedId) async {
    final current = flow(aedId);
    _update(aedId, current.copyWith(busy: true));
    try {
      await ref
          .read(reportServiceProvider)
          .submit(aedId, current.draft, current.idempotencyKey, DateTime.now().difference(current.openedAt));
      _update(aedId, flow(aedId).copyWith(busy: false, step: ReportStep.done));
    } catch (e) {
      _update(aedId, flow(aedId).copyWith(busy: false, error: e is ApiError ? e.code : 'network'));
    }
  }

  void reset(String aedId) => state = {...state}..remove(aedId);
}

final reportProvider = NotifierProvider<ReportNotifier, Map<String, ReportFlow>>(ReportNotifier.new);
