import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/local/tables.dart';
import 'package:expense_manager/providers/analytics_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_db.dart';

DateTime daysAgo(int days, {int hour = 12}) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - days, hour);
}

double trendTotal(AnalyticsProvider p) =>
    p.trend.fold(0.0, (sum, point) => sum + point.expense);

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDb());
  tearDown(() async => db.close());

  Future<AnalyticsProvider> load([AnalyticsPeriod? period]) async {
    final p = AnalyticsProvider(db);
    if (period != null) p.setPeriod(period);
    await p.load();
    return p;
  }

  Future<void> seedToday() async {
    await addTxn(db, amount: 100, category: 'Food', date: daysAgo(0));
    await addTxn(db, amount: 50, category: 'Travel', date: daysAgo(0));
    await addTxn(db,
        amount: 1000,
        type: TransactionType.income,
        category: 'Salary',
        date: daysAgo(0));
  }

  group('totals', () {
    test('income, expenses and net savings', () async {
      await seedToday();

      final p = await load();

      expect(p.income, 1000);
      expect(p.expense, 150);
      expect(p.netSavings, 850);
    });

    test('empty database gives zeros and no categories', () async {
      final p = await load();

      expect(p.income, 0);
      expect(p.expense, 0);
      expect(p.netSavings, 0);
      expect(p.categoryTotals, isEmpty);
    });

    test('soft-deleted transactions are excluded', () async {
      await seedToday();
      await addTxn(db, amount: 999, deleted: true, date: daysAgo(0));

      final p = await load();

      expect(p.expense, 150);
    });

    test('transactions outside the period are excluded', () async {
      await seedToday();
      await addTxn(db, amount: 777, date: daysAgo(800));

      final p = await load(AnalyticsPeriod.year);

      expect(p.expense, 150);
    });
  });

  group('category breakdown', () {
    test('expense categories only, largest first', () async {
      await seedToday();

      final p = await load();

      expect(p.categoryTotals.keys.toList(), ['Food', 'Travel']);
      expect(p.categoryTotals['Food'], 100);
      expect(p.categoryTotals['Travel'], 50);
      expect(p.categoryTotals.containsKey('Salary'), isFalse);
    });
  });

  group('trend buckets', () {
    test('month: one bucket per day so far, today is the last', () async {
      await seedToday();

      final p = await load(AnalyticsPeriod.month);

      expect(p.trend.length, DateTime.now().day);
      expect(p.trend.last.expense, 150);
      expect(trendTotal(p), p.expense);
    });

    test('week: 7 daily buckets, oldest first', () async {
      await seedToday();
      await addTxn(db, amount: 40, date: daysAgo(3));

      final p = await load(AnalyticsPeriod.week);

      expect(p.trend.length, 7);
      expect(p.trend[6].expense, 150);
      expect(p.trend[3].expense, 40);
      expect(p.expense, 190);
      expect(trendTotal(p), 190);
    });

    test('3 months: weekly buckets that add up to the total', () async {
      await seedToday();
      await addTxn(db, amount: 40, date: daysAgo(40));

      final p = await load(AnalyticsPeriod.threeMonths);

      expect(p.expense, 190);
      expect(trendTotal(p), 190);
      expect(p.trend.last.expense, 150);
    });

    test('year: 12 monthly buckets that add up to the total', () async {
      await seedToday();
      await addTxn(db, amount: 40, date: daysAgo(40));

      final p = await load(AnalyticsPeriod.year);

      expect(p.trend.length, 12);
      expect(p.expense, 190);
      expect(trendTotal(p), 190);
      expect(p.trend.last.expense, greaterThanOrEqualTo(150));
    });
  });

  group('switching period', () {
    test('week excludes a 20-day-old expense, year includes it', () async {
      await seedToday();
      await addTxn(db, amount: 25, date: daysAgo(20));

      final p = await load(AnalyticsPeriod.week);
      expect(p.period, AnalyticsPeriod.week);
      expect(p.expense, 150);

      p.setPeriod(AnalyticsPeriod.year);
      await p.load();
      expect(p.period, AnalyticsPeriod.year);
      expect(p.expense, 175);
    });
  });
}