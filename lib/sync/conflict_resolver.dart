// lib/sync/conflict_resolver.dart
import 'dart:convert';

class ConflictResolver {
  /// Merges non-conflicting fields independently using field-level timestamps.
  /// Falls back to Last-Write-Wins (LWW) via updatedAt when timestamps collide.
  static Map<String, dynamic> resolveFieldLevelConflict({
    required Map<String, dynamic> localRecord,
    required Map<String, dynamic> remoteRecord,
  }) {
    final Map<String, dynamic> localTimes = localRecord['field_timestamps'] != null
        ? (localRecord['field_timestamps'] is String
        ? jsonDecode(localRecord['field_timestamps'] as String)
        : localRecord['field_timestamps'] as Map<String, dynamic>)
        : {};

    final Map<String, dynamic> remoteTimes = remoteRecord['field_timestamps'] != null
        ? (remoteRecord['field_timestamps'] is String
        ? jsonDecode(remoteRecord['field_timestamps'] as String)
        : remoteRecord['field_timestamps'] as Map<String, dynamic>)
        : {};

    final merged = Map<String, dynamic>.from(remoteRecord);

    final fields = [
      'amount',
      'type',
      'category_id',
      'account_id',
      'note',
      'transaction_date',
    ];

    final defaultLocalUpdated = localRecord['updated_at'] != null
        ? (localRecord['updated_at'] is DateTime
        ? localRecord['updated_at'] as DateTime
        : DateTime.parse(localRecord['updated_at'].toString()))
        : DateTime.fromMillisecondsSinceEpoch(0);

    final defaultRemoteUpdated = remoteRecord['updated_at'] != null
        ? (remoteRecord['updated_at'] is DateTime
        ? remoteRecord['updated_at'] as DateTime
        : DateTime.parse(remoteRecord['updated_at'].toString()))
        : DateTime.fromMillisecondsSinceEpoch(0);

    for (final field in fields) {
      if (!localRecord.containsKey(field) && !remoteRecord.containsKey(field)) {
        continue;
      }

      final localStamp = localTimes[field] != null
          ? DateTime.parse(localTimes[field].toString())
          : defaultLocalUpdated;

      final remoteStamp = remoteTimes[field] != null
          ? DateTime.parse(remoteTimes[field].toString())
          : defaultRemoteUpdated;

      // If local change for this specific field is newer, retain local value
      if (localStamp.isAfter(remoteStamp)) {
        merged[field] = localRecord[field];
      }
    }

    // Force syncStatus to 'synced' post-resolution
    merged['syncStatus'] = 'synced';

    return merged;
  }
}