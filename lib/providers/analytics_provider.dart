import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

enum AnalyticsPeriod { week, month, threeMonths, year }

class TrendPoint {
  final String label;
  final double expense;
  const TrendPoint(this.label, this.expense);
}

class AnalyticsProvider extends ChangeNotifier {
  final AppDatabase _db;
  AnalyticsPeriod _period = AnalyticsPeriod.month;
  double _income = 0;
  double _expense = 0;
  Map<String, double> _categoryTotals = {};
  List<TrendPoint> _trend = [];

  AnalyticsProvider(this._db) {
    load();
  }

  AnalyticsPeriod get period => _period;
  double get income => _income;
  double get expense => _expense;
  double get netSavings => _income - _expense;
  Map<String, double> get categoryTotals => _categoryTotals;
  List<TrendPoint> get trend => _trend;

  void setPeriod(AnalyticsPeriod p) {
    _period = p;
    load();
  }

  Future<void> load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(const Duration(days: 1));

    late DateTime start;
    late int count;
    late int Function(DateTime) indexOf;
    late String Function(int) labelOf;

    switch (_period) {
      case AnalyticsPeriod.week:
        start = today.subtract(const Duration(days: 6));
        count = 7;
        indexOf = (d) => DateTime(d.year, d.month, d.day).difference(start).inDays;
        labelOf = (i) => DateFormat('E').format(start.add(Duration(days: i)));
        break;
      case AnalyticsPeriod.month:
        start = DateTime(now.year, now.month, 1);
        count = now.day;
        indexOf = (d) => d.day - 1;
        labelOf = (i) => '${i + 1}';
        break;
      case AnalyticsPeriod.threeMonths:
        start = DateTime(now.year, now.month - 2, 1);
        count = end.difference(start).inDays ~/ 7 + 1;
        indexOf = (d) => DateTime(d.year, d.month, d.day).difference(start).inDays ~/ 7;
        labelOf = (i) =>
            DateFormat('d MMM').format(start.add(Duration(days: i * 7)));
        break;
      case AnalyticsPeriod.year:
        start = DateTime(now.year, now.month - 11, 1);
        count = 12;
        indexOf = (d) => (d.year - start.year) * 12 + d.month - start.month;
        labelOf = (i) =>
            DateFormat('MMM').format(DateTime(start.year, start.month + i, 1));
        break;
    }

    final rows = await _db.getTransactionsBetween(start, end);

    double income = 0;
    double expense = 0;
    final cats = <String, double>{};
    final buckets = List<double>.filled(count, 0);

    for (final t in rows) {
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
        cats[t.categoryId] = (cats[t.categoryId] ?? 0) + t.amount;
        final i = indexOf(t.transactionDate);
        if (i >= 0 && i < count) buckets[i] += t.amount;
      }
    }

    _income = income;
    _expense = expense;
    _categoryTotals = Map.fromEntries(
      cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    _trend = [for (var i = 0; i < count; i++) TrendPoint(labelOf(i), buckets[i])];
    notifyListeners();
  }
}