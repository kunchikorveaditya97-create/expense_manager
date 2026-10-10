// lib/data/repositories/budget_repository.dart
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local/app_database.dart';
import '../local/tables.dart';

abstract class IBudgetRepository {
  Future<double> getMonthlyBudget(int month, int year);
  Future<void> setMonthlyBudget({
    required double amount,
    required int month,
    required int year,
  });
  Future<double> getMonthTotalExpenses(int month, int year);
}

class BudgetRepositoryImpl implements IBudgetRepository {
  final AppDatabase _db;

  BudgetRepositoryImpl(this._db);

  @override
  Future<double> getMonthlyBudget(int month, int year) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('budget_${year}_$month') ?? 0.0;
  }

  @override
  Future<void> setMonthlyBudget({
    required double amount,
    required int month,
    required int year,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('budget_${year}_$month', amount);
  }

  @override
  Future<double> getMonthTotalExpenses(int month, int year) async {
    final start = DateTime.utc(year, month, 1);
    final end = DateTime.utc(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final query = _db.select(_db.transactions)
      ..where((t) =>
      t.type.equals(TransactionType.expense.index) &
      t.deletedAt.isNull() &
      t.transactionDate.isBiggerOrEqualValue(start) &
      t.transactionDate.isSmallerOrEqualValue(end));

    final expenses = await query.get();
    return expenses.fold<double>(0.0, (sum, item) => sum + item.amount);
  }
}