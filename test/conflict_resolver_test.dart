// test/conflict_resolver_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_manager/sync/conflict_resolver.dart';

void main() {
  group('ConflictResolver Tests', () {
    test('Resolves field-level conflicts preserving non-overlapping changes', () {
      final now = DateTime.now().toUtc();

      // Device A changed amount at now
      final localRecord = {
        'id': 'txn-1',
        'amount': 250.0,
        'note': 'Initial Note',
        'updated_at': now.toIso8601String(),
        'field_timestamps': jsonEncode({
          'amount': now.toIso8601String(),
        }),
      };

      // Device B changed note 1 minute earlier
      final remoteRecord = {
        'id': 'txn-1',
        'amount': 100.0,
        'note': 'Dinner with family',
        'updated_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
        'field_timestamps': jsonEncode({
          'note': now.add(const Duration(seconds: 10)).toIso8601String(),
        }),
      };

      final merged = ConflictResolver.resolveFieldLevelConflict(
        localRecord: localRecord,
        remoteRecord: remoteRecord,
      );

      // Assert field preservation
      expect(merged['amount'], 250.0);
      expect(merged['note'], 'Dinner with family');
      expect(merged['syncStatus'], 'synced');
    });
  });
}