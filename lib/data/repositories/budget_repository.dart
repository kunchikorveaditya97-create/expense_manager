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
  Future<Map<String, double>> getCategoryBudgets(int month, int year);
  Future<Map<String, double>> getCategorySpend(int month, int year);
  Future<void> setCategoryBudget({
    required String category,
    required double amount,
    required int month,
    required int year,
  });
}

class BudgetRepositoryImpl implements IBudgetRepository {
  final AppDatabase _db;

  BudgetRepositoryImpl(this._db);

  String _legacyKey(int month, int year) => 'budget_${year}_$month';

  @override
  Future<double> getMonthlyBudget(int month, int year) async {
    final fromDb = await _db.getBudgetLimit('ALL', month, year);
    if (fromDb != null) return fromDb;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_legacyKey(month, year)) ?? 0.0;
  }

  @override
  Future<void> setMonthlyBudget({
    required double amount,
    required int month,
    required int year,
  }) async {
    await _db.setBudgetLimit('ALL', month, year, amount);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey(month, year));
  }

  @override
  Future<double> getMonthTotalExpenses(int month, int year) {
    return _db.getTotalBetween(
      TransactionType.expense,
      DateTime(year, month, 1),
      DateTime(year, month + 1, 1),
    );
  }

  @override
  Future<Map<String, double>> getCategoryBudgets(int month, int year) =>
      _db.getCategoryBudgets(month, year);

  @override
  Future<Map<String, double>> getCategorySpend(int month, int year) =>
      _db.getExpenseByCategory(
          DateTime(year, month, 1), DateTime(year, month + 1, 1));

  @override
  Future<void> setCategoryBudget({
    required String category,
    required double amount,
    required int month,
    required int year,
  }) =>
      _db.setBudgetLimit(category, month, year, amount);
}