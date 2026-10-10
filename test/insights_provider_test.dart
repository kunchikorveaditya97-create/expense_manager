import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/local/tables.dart';
import 'package:expense_manager/providers/insights_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_db.dart';

// Wednesday 14 Oct 2026, 15:00. Week = Mon 12 Oct .. today.
// "Same days last week" = Mon 5 .. Wed 7 Oct.
// "Same days last month" = 1 .. 14 Sep.
final wed = DateTime(2026, 10, 14, 15);

String money(double v) => '\$${v.toStringAsFixed(0)}';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDb());
  tearDown(() async => db.close());

  Future<List<String>> insightsAt(DateTime now) async {
    final p = InsightsProvider(db, clock: () => now);
    p.formatAmount = money;
    await p.generateInsights();
    return p.insights;
  }

  test('no transactions: no insights', () async {
    expect(await insightsAt(wed), isEmpty);
  });

  group('week over week', () {
    test('spent more than the same days last week', () async {
      await addTxn(db, amount: 100, date: DateTime(2026, 10, 6, 12)); // last Tue
      await addTxn(db, amount: 120, date: DateTime(2026, 10, 13, 12)); // this Tue

      final list = await insightsAt(wed);

      expect(list, contains('You spent 20% more this week than last week.'));
    });

    test('spent less than the same days last week', () async {
      await addTxn(db, amount: 200, date: DateTime(2026, 10, 7, 12)); // last Wed
      await addTxn(db, amount: 100, date: DateTime(2026, 10, 12, 12)); // this Mon

      final list = await insightsAt(wed);

      expect(list,
          contains('Your spending decreased by 50% compared to last week.'));
    });

    test('early in the week it does not compare against all of last week',
            () async {
          final monday = DateTime(2026, 10, 12, 9);
          await addTxn(db, amount: 50, date: DateTime(2026, 10, 5, 12)); // last Mon
          await addTxn(db, amount: 500, date: DateTime(2026, 10, 9, 12)); // last Fri
          await addTxn(db, amount: 50, date: DateTime(2026, 10, 12, 8)); // today

          final list = await insightsAt(monday);

          // Monday vs Monday is flat, so no week insight at all.
          expect(list.where((s) => s.contains('last week')), isEmpty);
        });

    test('nothing last week: no week insight', () async {
      await addTxn(db, amount: 100, date: DateTime(2026, 10, 13, 12));

      final list = await insightsAt(wed);

      expect(list.where((s) => s.contains('last week')), isEmpty);
    });
  });

  group('month over month', () {
    test('decrease, compared over the same days only', () async {
      await addTxn(db, amount: 1000, date: DateTime(2026, 9, 3, 12));
      // After the 14th, so it must NOT count against this month's total.
      await addTxn(db, amount: 5000, date: DateTime(2026, 9, 20, 12));
      await addTxn(db, amount: 880, date: DateTime(2026, 10, 2, 12));

      final list = await insightsAt(wed);

      expect(list,
          contains('Your spending decreased by 12% compared with last month.'));
    });

    test('increase', () async {
      await addTxn(db, amount: 500, date: DateTime(2026, 9, 3, 12));
      await addTxn(db, amount: 600, date: DateTime(2026, 10, 2, 12));

      final list = await insightsAt(wed);

      expect(list,
          contains('Your spending increased by 20% compared with last month.'));
    });

    test('works across a year boundary (January vs December)', () async {
      final jan = DateTime(2027, 1, 15, 10);
      await addTxn(db, amount: 100, date: DateTime(2026, 12, 3, 12));
      await addTxn(db, amount: 50, date: DateTime(2027, 1, 5, 12));

      final list = await insightsAt(jan);

      expect(list,
          contains('Your spending decreased by 50% compared with last month.'));
    });
  });

  group('averages and categories', () {
    test('average daily spending = month spent / day of month', () async {
      await addTxn(db, amount: 140, date: DateTime(2026, 10, 3, 12)); // 140 / 14

      final list = await insightsAt(wed);

      expect(list, contains('Your average daily spending this month is \$10.'));
    });

    test('income and deleted transactions are ignored', () async {
      await addTxn(db, amount: 140, date: DateTime(2026, 10, 3, 12));
      await addTxn(db,
          amount: 5000,
          type: TransactionType.income,
          category: 'Salary',
          date: DateTime(2026, 10, 3, 12));
      await addTxn(db,
          amount: 999, deleted: true, date: DateTime(2026, 10, 3, 12));

      final list = await insightsAt(wed);

      expect(list, contains('Your average daily spending this month is \$10.'));
      expect(list, isNot(contains('Salary is your highest expense category this month.')));
    });

    test('highest expense category this month', () async {
      await addTxn(db,
          amount: 300, category: 'Food', date: DateTime(2026, 10, 2, 12));
      await addTxn(db,
          amount: 100, category: 'Travel', date: DateTime(2026, 10, 3, 12));

      final list = await insightsAt(wed);

      expect(list,
          contains('Food is your highest expense category this month.'));
    });

    test('last month\'s top category does not leak into this month', () async {
      await addTxn(db,
          amount: 900, category: 'Rent', date: DateTime(2026, 9, 2, 12));
      await addTxn(db,
          amount: 50, category: 'Food', date: DateTime(2026, 10, 2, 12));

      final list = await insightsAt(wed);

      expect(list,
          contains('Food is your highest expense category this month.'));
    });
  });
}