// lib/sync/conflict_resolver.dart
//
// Field-level merge for synced records. Pure Dart (no Flutter / Firebase /
// Drift imports) so it is trivially unit-testable.
//
// Records are plain maps in the *cloud* format (snake_case keys, ISO-8601
// strings for dates). Every record may carry `field_timestamps`:
//   { "amount": "2026-07-01T10:00:00.000Z", "note": "...", ... }
// i.e. the last time each field was changed on the device that changed it.
import 'dart:convert';

class MergeResult {
  const MergeResult(this.record, this.needsPush);

  /// The merged record, cloud format (field_timestamps is a Map).
  final Map<String, dynamic> record;

  /// True when at least one field value came from the local side and differs
  /// from the remote, so the merged record must be uploaded.
  final bool needsPush;
}

class ConflictResolver {
  ConflictResolver._();

  static const transactionFields = <String>[
    'amount',
    'type',
    'category_id',
    'account_id',
    'note',
    'transaction_date',
    'deleted_at',
  ];
  static const accountFields = <String>[
    'name',
    'type',
    'initial_balance',
    'deleted_at',
  ];
  static const goalFields = <String>[
    'name',
    'target_amount',
    'current_amount',
    'target_date',
    'icon_name',
    'deleted_at',
  ];

  static final DateTime _epoch =
  DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  static final RegExp _isoLike = RegExp(r'^\d{4}-\d{2}-\d{2}T');

  /// Merges [local] and [remote] one field at a time.
  ///
  /// * A field changed on only one side keeps that side's value (that side's
  ///   per-field timestamp is the newest, because the other side's timestamp
  ///   is still the old baseline).
  /// * A field changed on both sides falls back to Last-Write-Wins using the
  ///   per-field timestamp, then the record's `updated_at`, then a
  ///   deterministic value comparison, so every device converges on the same
  ///   result regardless of which side calls it "local".
  /// * Records without `field_timestamps` (legacy rows, accounts, goals) use
  ///   the record `updated_at` as the timestamp for every field, which makes
  ///   the merge degrade to plain whole-record LWW.
  ///
  /// When the local side contributes a value, `updated_at` is bumped to [now]
  /// so other devices that already hold the remote version will accept the
  /// merged one.
  static MergeResult merge({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    List<String> fields = transactionFields,
    DateTime? now,
  }) {
    final lStamps = _stamps(local['field_timestamps']);
    final rStamps = _stamps(remote['field_timestamps']);
    final lUpdated = parseTime(local['updated_at']) ?? _epoch;
    final rUpdated = parseTime(remote['updated_at']) ?? _epoch;

    final merged = Map<String, dynamic>.from(remote);
    final stamps = <String, String>{};
    var needsPush = false;

    for (final f in fields) {
      final lv = local[f];
      final rv = remote[f];
      final ls = parseTime(lStamps[f]) ?? lUpdated;
      final rs = parseTime(rStamps[f]) ?? rUpdated;

      if (_same(lv, rv)) {
        merged[f] = rv;
        stamps[f] = (ls.isAfter(rs) ? ls : rs).toIso8601String();
        continue;
      }

      if (_localWins(ls, rs, lUpdated, rUpdated, lv, rv)) {
        merged[f] = lv;
        stamps[f] = ls.toIso8601String();
        needsPush = true;
      } else {
        merged[f] = rv;
        stamps[f] = rs.toIso8601String();
      }
    }

    var updated = lUpdated.isAfter(rUpdated) ? lUpdated : rUpdated;
    if (needsPush) {
      final bump = (now ?? DateTime.now()).toUtc();
      if (bump.isAfter(updated)) updated = bump;
    }

    merged['field_timestamps'] = stamps;
    merged['updated_at'] = updated.toIso8601String();
    return MergeResult(merged, needsPush);
  }

  static bool _localWins(DateTime ls, DateTime rs, DateTime lu, DateTime ru,
      dynamic lv, dynamic rv) {
    final byField = ls.compareTo(rs);
    if (byField != 0) return byField > 0;
    final byRecord = lu.compareTo(ru);
    if (byRecord != 0) return byRecord > 0;
    // Exact tie: pick by value so both devices choose the same winner.
    return '$lv'.compareTo('$rv') > 0;
  }

  static bool _same(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return a == b;
    if (a is String && b is String && _isoLike.hasMatch(a) && _isoLike.hasMatch(b)) {
      final da = DateTime.tryParse(a);
      final db = DateTime.tryParse(b);
      if (da != null && db != null) return da.isAtSameMomentAs(db);
    }
    return a == b;
  }

  static Map<String, dynamic> _stamps(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  static DateTime? parseTime(dynamic v) {
    if (v is DateTime) return v.toUtc();
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    return null;
  }
}

/// Builds the JSON stored in `Transactions.fieldTimestamps`.
class FieldTimestamps {
  FieldTimestamps._();

  /// All fields stamped with the creation time.
  static String forCreate(DateTime at,
      {List<String> fields = ConflictResolver.transactionFields}) {
    final iso = at.toUtc().toIso8601String();
    return jsonEncode({for (final f in fields) f: iso});
  }

  /// Stamps only [changed] fields with [now]. Every other field keeps its
  /// existing stamp, or [baseline] (the row's previous `updatedAt`) when it
  /// has none yet, so an edit to one field never makes the rest look new.
  static String touch(
      String? existingJson,
      Iterable<String> changed,
      DateTime now, {
        required DateTime baseline,
        List<String> fields = ConflictResolver.transactionFields,
      }) {
    final existing = <String, dynamic>{};
    if (existingJson != null && existingJson.isNotEmpty) {
      try {
        final d = jsonDecode(existingJson);
        if (d is Map) existing.addAll(Map<String, dynamic>.from(d));
      } catch (_) {}
    }
    final base = baseline.toUtc().toIso8601String();
    final out = <String, String>{
      for (final f in fields) f: existing[f]?.toString() ?? base,
    };
    final nowIso = now.toUtc().toIso8601String();
    for (final f in changed) {
      out[f] = nowIso;
    }
    return jsonEncode(out);
  }
}