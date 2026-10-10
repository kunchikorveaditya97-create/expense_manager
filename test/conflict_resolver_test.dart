import 'dart:convert';

import 'package:expense_manager/sync/conflict_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

const base = '2026-07-01T00:00:00.000Z';
const t10 = '2026-07-01T10:00:00.000Z';
const t11 = '2026-07-01T11:00:00.000Z';
const t12 = '2026-07-01T12:00:00.000Z';

Map<String, String> stamps([Map<String, String> over = const {}]) => {
  for (final f in ConflictResolver.transactionFields) f: base,
  ...over,
};

Map<String, dynamic> rec({
  double amount = 20,
  String? note = 'Lunch',
  String? deletedAt,
  required String updated,
  Map<String, String>? fieldStamps,
}) =>
    {
      'id': 't1',
      'amount': amount,
      'type': 'expense',
      'category_id': 'Food',
      'account_id': 'a1',
      'note': note,
      'transaction_date': '2026-07-01T10:00:00.000Z',
      'deleted_at': deletedAt,
      'updated_at': updated,
      if (fieldStamps != null) 'field_timestamps': fieldStamps,
    };

void main() {
  final now = DateTime.utc(2026, 7, 1, 13);

  group('ConflictResolver.merge', () {
    test('note edit on A and amount edit on B both survive', () {
      final a = rec(note: 'Dinner', updated: t10, fieldStamps: stamps({'note': t10}));
      final b = rec(amount: 30, updated: t11, fieldStamps: stamps({'amount': t11}));

      final r = ConflictResolver.merge(local: a, remote: b, now: now);

      expect(r.record['amount'], 30);
      expect(r.record['note'], 'Dinner');
      expect(r.needsPush, isTrue); // merged result must be uploaded
      // bumped so devices already holding B's version accept the merge
      expect(DateTime.parse(r.record['updated_at'] as String), now);
    });

    test('same field on both sides: newer field timestamp wins', () {
      final a = rec(amount: 25, updated: t12, fieldStamps: stamps({'amount': t12}));
      final b = rec(amount: 30, updated: t11, fieldStamps: stamps({'amount': t11}));

      final localNewer = ConflictResolver.merge(local: a, remote: b, now: now);
      expect(localNewer.record['amount'], 25);
      expect(localNewer.needsPush, isTrue);

      final remoteNewer = ConflictResolver.merge(local: b, remote: a, now: now);
      expect(remoteNewer.record['amount'], 25);
      expect(remoteNewer.needsPush, isFalse);
    });

    test('exact tie resolves identically on both devices', () {
      final a = rec(amount: 25, updated: t10, fieldStamps: stamps({'amount': t10}));
      final b = rec(amount: 30, updated: t10, fieldStamps: stamps({'amount': t10}));

      final onA = ConflictResolver.merge(local: a, remote: b, now: now);
      final onB = ConflictResolver.merge(local: b, remote: a, now: now);

      expect(onA.record['amount'], onB.record['amount']);
    });

    test('delete beats an older edit, but a newer restore beats the delete', () {
      final deletedLocally = rec(
        deletedAt: t12,
        updated: t12,
        fieldStamps: stamps({'deleted_at': t12}),
      );
      final editedRemotely = rec(
        amount: 99,
        updated: t11,
        fieldStamps: stamps({'amount': t11}),
      );
      final r =
      ConflictResolver.merge(local: deletedLocally, remote: editedRemotely, now: now);
      expect(r.record['deleted_at'], t12); // tombstone survives
      expect(r.record['amount'], 99); // remote edit still merged

      final restoredRemotely = rec(
        updated: '2026-07-01T12:30:00.000Z',
        fieldStamps: stamps({'deleted_at': '2026-07-01T12:30:00.000Z'}),
      );
      final r2 = ConflictResolver.merge(
          local: deletedLocally, remote: restoredRemotely, now: now);
      expect(r2.record['deleted_at'], isNull);
    });

    test('legacy rows without field_timestamps fall back to updated_at', () {
      final local = rec(amount: 25, updated: t12);
      final remote = rec(amount: 30, updated: t11);

      final r = ConflictResolver.merge(local: local, remote: remote, now: now);

      expect(r.record['amount'], 25);
      expect(r.needsPush, isTrue);
    });

    test('identical records need no push', () {
      final a = rec(updated: t10, fieldStamps: stamps());
      final r = ConflictResolver.merge(local: a, remote: Map.of(a), now: now);
      expect(r.needsPush, isFalse);
    });

    test('25 and 25.0 are treated as the same value', () {
      final a = rec(amount: 25, updated: t10, fieldStamps: stamps());
      final b = rec(updated: t11, fieldStamps: stamps())..['amount'] = 25;
      expect(ConflictResolver.merge(local: a, remote: b, now: now).needsPush, isFalse);
    });
  });

  group('FieldTimestamps', () {
    test('touch stamps only changed fields; others keep the baseline', () {
      final json = FieldTimestamps.touch(
        null,
        const ['note'],
        DateTime.utc(2026, 7, 2),
        baseline: DateTime.utc(2026, 7, 1),
      );
      final m = jsonDecode(json) as Map<String, dynamic>;

      expect(m['note'], startsWith('2026-07-02'));
      expect(m['amount'], startsWith('2026-07-01'));
      expect(m.keys, containsAll(ConflictResolver.transactionFields));
    });

    test('touch keeps existing stamps of untouched fields', () {
      final first = FieldTimestamps.forCreate(DateTime.utc(2026, 6, 1));
      final second = FieldTimestamps.touch(
        first,
        const ['amount'],
        DateTime.utc(2026, 7, 2),
        baseline: DateTime.utc(2026, 7, 1),
      );
      final m = jsonDecode(second) as Map<String, dynamic>;

      expect(m['note'], startsWith('2026-06-01'));
      expect(m['amount'], startsWith('2026-07-02'));
    });
  });
}