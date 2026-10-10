import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class InsightsProvider extends ChangeNotifier {
  final AppDatabase _db;
  final DateTime Function() _clock;
  List<String> _insights = [];
  String Function(double) formatAmount = (v) => v.toStringAsFixed(0);

  InsightsProvider(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    generateInsights();
  }

  List<String> get insights => _insights;

  Future<void> generateInsights() async {
    final now = _clock();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final list = <String>[];

    final thisWeekStart =
    DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final lastWeekStart = DateTime(
        thisWeekStart.year, thisWeekStart.month, thisWeekStart.day - 7);
    final lastWeekEnd = DateTime(
        lastWeekStart.year, lastWeekStart.month, lastWeekStart.day + now.weekday);

    final thisWeekSpent = await _expensesBetween(thisWeekStart, tomorrow);
    final lastWeekSpent = await _expensesBetween(lastWeekStart, lastWeekEnd);

    if (lastWeekSpent > 0) {
      final diff =
      ((thisWeekSpent - lastWeekSpent) / lastWeekSpent * 100).round();
      if (diff > 0) {
        list.add('You spent $diff% more this week than last week.');
      } else if (diff < 0) {
        list.add(
            'Your spending decreased by ${diff.abs()}% compared to last week.');
      }
    }

    final firstThisMonth = DateTime(now.year, now.month, 1);
    final firstLastMonth = DateTime(now.year, now.month - 1, 1);
    final lastMonthLength = DateTime(now.year, now.month, 0).day;
    final lastMonthEnd = DateTime(firstLastMonth.year, firstLastMonth.month,
        math.min(now.day, lastMonthLength) + 1);

    final thisMonthSpent = await _expensesBetween(firstThisMonth, tomorrow);
    final lastMonthSpent = await _expensesBetween(firstLastMonth, lastMonthEnd);

    if (lastMonthSpent > 0) {
      final diff =
      ((thisMonthSpent - lastMonthSpent) / lastMonthSpent * 100).round();
      if (diff < 0) {
        list.add(
            'Your spending decreased by ${diff.abs()}% compared with last month.');
      } else if (diff > 0) {
        list.add('Your spending increased by $diff% compared with last month.');
      }
    }

    if (thisMonthSpent > 0) {
      final dailyAvg = thisMonthSpent / now.day;
      list.add(
          'Your average daily spending this month is ${formatAmount(dailyAvg)}.');
    }

    final topCategory = await _topExpenseCategory(firstThisMonth, tomorrow);
    if (topCategory != null && topCategory.isNotEmpty) {
      list.add('$topCategory is your highest expense category this month.');
    }

    _insights = list;
    notifyListeners();
  }

  Future<double> _expensesBetween(DateTime start, DateTime end) async {
    final amountSum = _db.transactions.amount.sum();
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([amountSum])
      ..where(_db.transactions.type.equalsValue(TransactionType.expense))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.transactionDate.isBiggerOrEqualValue(start))
      ..where(_db.transactions.transactionDate.isSmallerThanValue(end));
    final row = await query.getSingle();
    return row.read(amountSum) ?? 0.0;
  }

  Future<String?> _topExpenseCategory(DateTime start, DateTime end) async {
    final amountSum = _db.transactions.amount.sum();
    final catCol = _db.transactions.categoryId;
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([catCol, amountSum])
      ..where(_db.transactions.type.equalsValue(TransactionType.expense))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.transactionDate.isBiggerOrEqualValue(start))
      ..where(_db.transactions.transactionDate.isSmallerThanValue(end))
      ..groupBy([catCol])
      ..orderBy([OrderingTerm.desc(amountSum)])
      ..limit(1);

    final row = await query.getSingleOrNull();
    return row?.read(catCol);
  }
}