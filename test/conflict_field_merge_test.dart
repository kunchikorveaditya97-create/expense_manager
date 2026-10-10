import 'dart:convert';

import 'package:expense_manager/sync/conflict_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

const t0 = '2026-07-01T10:00:00.000Z';
const t1 = '2026-07-01T11:00:00.000Z';
const t2 = '2026-07-01T12:00:00.000Z';

Map<String, dynamic> rec({
  required num amount,
  String? note,
  required String updatedAt,
  Map<String, String>? stamps,
  String? deletedAt,
}) =>
    {
      'id': 't1',
      'amount': amount,
      'type': 'expense',
      'category_id': 'Food',
      'account_id': 'acc1',
      'note': note,
      'transaction_date': '2026-07-01T09:00:00.000Z',
      'deleted_at': deletedAt,
      'updated_at': updatedAt,
      'field_timestamps': stamps ?? <String, String>{},
    };

void main() {
  group('ConflictResolver.merge (field level)', () {
    test('different fields changed on each device: both changes survive', () {
      final local = rec(
        amount: 20,
        note: 'lunch with team',
        updatedAt: t2,
        stamps: {'amount': t0, 'note': t2},
      );
      final remote = rec(
        amount: 30,
        note: 'lunch',
        updatedAt: t1,
        stamps: {'amount': t1, 'note': t0},
      );

      final r = ConflictResolver.merge(
        local: local,
        remote: remote,
        now: DateTime.parse('2026-07-01T13:00:00.000Z'),
      );

      expect(r.record['amount'], 30);
      expect(r.record['note'], 'lunch with team');
      expect(r.needsPush, isTrue);
    });

    test('same field changed on both sides: last write wins (local newer)', () {
      final local = rec(
          amount: 25, updatedAt: t2, stamps: {'amount': t2});
      final remote = rec(
          amount: 30, updatedAt: t1, stamps: {'amount': t1});

      final r = ConflictResolver.merge(local: local, remote: remote);

      expect(r.record['amount'], 25);
      expect(r.needsPush, isTrue);
    });

    test('same field changed on both sides: last write wins (remote newer)',
            () {
          final local = rec(
              amount: 25, updatedAt: t1, stamps: {'amount': t1});
          final remote = rec(
              amount: 30, updatedAt: t2, stamps: {'amount': t2});

          final r = ConflictResolver.merge(local: local, remote: remote);

          expect(r.record['amount'], 30);
          expect(r.needsPush, isFalse);
        });

    test('identical records need no push', () {
      final a = rec(amount: 20, note: 'x', updatedAt: t1, stamps: {'amount': t0});
      final b = rec(amount: 20, note: 'x', updatedAt: t1, stamps: {'amount': t0});

      final r = ConflictResolver.merge(local: a, remote: b);

      expect(r.needsPush, isFalse);
      expect(r.record['amount'], 20);
      expect(r.record['note'], 'x');
    });

    test('exact timestamp tie converges to the same value on both devices', () {
      final a = rec(amount: 25, updatedAt: t1, stamps: {'amount': t1});
      final b = rec(amount: 30, updatedAt: t1, stamps: {'amount': t1});

      final onDeviceA = ConflictResolver.merge(local: a, remote: b);
      final onDeviceB = ConflictResolver.merge(local: b, remote: a);

      expect(onDeviceA.record['amount'], onDeviceB.record['amount']);
    });

    test('delete on one device, note edit on another: both survive', () {
      final local = rec(
        amount: 20,
        note: 'lunch',
        updatedAt: t2,
        deletedAt: t2,
        stamps: {'deleted_at': t2, 'note': t0},
      );
      final remote = rec(
        amount: 20,
        note: 'lunch edited',
        updatedAt: t1,
        stamps: {'note': t1, 'deleted_at': t0},
      );

      final r = ConflictResolver.merge(local: local, remote: remote);

      expect(r.record['deleted_at'], t2);
      expect(r.record['note'], 'lunch edited');
      expect(r.needsPush, isTrue);
    });

    test('records without field_timestamps fall back to whole-record LWW', () {
      final local = rec(amount: 50, note: 'local', updatedAt: t2);
      final remote = rec(amount: 10, note: 'remote', updatedAt: t1);

      final r = ConflictResolver.merge(local: local, remote: remote);

      expect(r.record['amount'], 50);
      expect(r.record['note'], 'local');
    });

    test('merged updated_at is bumped when local contributes', () {
      final local = rec(amount: 25, updatedAt: t1, stamps: {'amount': t2});
      final remote = rec(amount: 30, updatedAt: t1, stamps: {'amount': t0});
      final now = DateTime.parse('2026-07-02T08:00:00.000Z');

      final r = ConflictResolver.merge(local: local, remote: remote, now: now);

      expect(r.needsPush, isTrue);
      expect(DateTime.parse(r.record['updated_at'] as String), now);
    });
  });

  group('FieldTimestamps', () {
    test('forCreate stamps every field with the creation time', () {
      final at = DateTime.parse(t0);
      final map = jsonDecode(FieldTimestamps.forCreate(at)) as Map;

      for (final f in ConflictResolver.transactionFields) {
        expect(DateTime.parse(map[f] as String), at);
      }
    });

    test('touch updates only the changed field', () {
      final baseline = DateTime.parse(t0);
      final now = DateTime.parse(t2);

      final json = FieldTimestamps.touch(
        null,
        const ['note'],
        now,
        baseline: baseline,
      );
      final map = jsonDecode(json) as Map;

      expect(DateTime.parse(map['note'] as String), now);
      expect(DateTime.parse(map['amount'] as String), baseline);
    });

    test('touch keeps existing stamps of untouched fields', () {
      final existing = jsonEncode({'amount': t1});
      final json = FieldTimestamps.touch(
        existing,
        const ['note'],
        DateTime.parse(t2),
        baseline: DateTime.parse(t0),
      );
      final map = jsonDecode(json) as Map;

      expect(DateTime.parse(map['amount'] as String), DateTime.parse(t1));
    });
  });
}