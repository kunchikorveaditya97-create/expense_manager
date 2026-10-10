// lib/providers/insights_provider.dart
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class InsightsProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<String> _insights = [];
  String Function(double) formatAmount = (v) => v.toStringAsFixed(0);

  InsightsProvider(this._db) {
    generateInsights();
  }

  List<String> get insights => _insights;

  Future<void> generateInsights() async {
    final now = DateTime.now();
    final List<String> list = [];

    // 1. Week-over-week calculation
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekStart.subtract(const Duration(milliseconds: 1));

    final thisWeekSpent = await _getExpensesBetween(thisWeekStart, now);
    final lastWeekSpent = await _getExpensesBetween(lastWeekStart, lastWeekEnd);

    if (lastWeekSpent > 0) {
      final diff = ((thisWeekSpent - lastWeekSpent) / lastWeekSpent) * 100;
      if (diff > 0) {
        list.add('You spent ${diff.toStringAsFixed(0)}% more this week than last week.');
      } else if (diff < 0) {
        list.add('Your spending decreased by ${diff.abs().toStringAsFixed(0)}% compared to last week.');
      }
    }

    // 2. Month-over-month calculation
    final firstDayThisMonth = DateTime(now.year, now.month, 1);
    final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);
    final lastDayLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);

    final thisMonthSpent = await _getExpensesBetween(firstDayThisMonth, now);
    final lastMonthSpent = await _getExpensesBetween(firstDayLastMonth, lastDayLastMonth);

    if (lastMonthSpent > 0) {
      final mDiff = ((thisMonthSpent - lastMonthSpent) / lastMonthSpent) * 100;
      if (mDiff < 0) {
        list.add('Your spending decreased by ${mDiff.abs().toStringAsFixed(0)}% compared with last month.');
      }
    }

    // 3. Average daily spending this month
    final daysPassed = now.day;
    if (daysPassed > 0 && thisMonthSpent > 0) {
      final dailyAvg = thisMonthSpent / daysPassed;
      list.add('Your average daily spending this month is ${formatAmount(dailyAvg)}.');
    }

    // 4. Top category
    final topCategory = await _getTopExpenseCategory(firstDayThisMonth, now);
    if (topCategory != null && topCategory.isNotEmpty) {
      list.add('$topCategory is your highest expense category this month.');
    }

    _insights = list;
    notifyListeners();
  }

  Future<double> _getExpensesBetween(DateTime start, DateTime end) async {
    final amountSum = _db.transactions.amount.sum();
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([amountSum])
      ..where(_db.transactions.type.equalsValue(TransactionType.expense))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.transactionDate.isBiggerOrEqualValue(start))
      ..where(_db.transactions.transactionDate.isSmallerOrEqualValue(end));
    final row = await query.getSingle();
    return row.read(amountSum) ?? 0.0;
  }

  Future<String?> _getTopExpenseCategory(DateTime start, DateTime end) async {
    final amountSum = _db.transactions.amount.sum();
    final catCol = _db.transactions.categoryId;
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([catCol, amountSum])
      ..where(_db.transactions.type.equalsValue(TransactionType.expense))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.transactionDate.isBiggerOrEqualValue(start))
      ..where(_db.transactions.transactionDate.isSmallerOrEqualValue(end))
      ..groupBy([catCol])
      ..orderBy([OrderingTerm.desc(amountSum)])
      ..limit(1);

    final row = await query.getSingleOrNull();
    return row?.read(catCol);
  }
}