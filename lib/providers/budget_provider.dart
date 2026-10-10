import 'package:flutter/foundation.dart';
import '../data/repositories/budget_repository.dart';

enum BudgetThreshold {
  safe,
  half,
  warning,
  critical,
  exceeded,
}

class CategoryBudgetStatus {
  final String category;
  final double limit;
  final double spent;
  const CategoryBudgetStatus(this.category, this.limit, this.spent);

  double get pct => limit > 0 ? spent / limit * 100 : 0;
  double get ratio => (pct / 100).clamp(0.0, 1.0);
  bool get exceeded => spent > limit;
  double get remaining => limit - spent;
}


class BudgetProvider extends ChangeNotifier {
  final IBudgetRepository _budgetRepo;

  double _monthlyBudget = 0.0;
  double _totalSpent = 0.0;
  bool _isLoading = false;

  List<CategoryBudgetStatus> _categoryStatuses = [];

  BudgetProvider(this._budgetRepo) {
    final now = DateTime.now();
    computeMonthlyBudget(now.month, now.year);
  }

  double get monthlyBudget => _monthlyBudget;
  double get totalSpent => _totalSpent;
  double get remaining => (_monthlyBudget - _totalSpent).clamp(0.0, double.infinity);
  double get exceededAmount => (_totalSpent > _monthlyBudget && _monthlyBudget > 0)
      ? (_totalSpent - _monthlyBudget)
      : 0.0;

  double get usedPercentage {
    if (_monthlyBudget <= 0) return 0.0;
    return (_totalSpent / _monthlyBudget) * 100.0;
  }

  double get progressRatio {
    if (_monthlyBudget <= 0) return 0.0;
    return (_totalSpent / _monthlyBudget).clamp(0.0, 1.0);
  }

  bool get isOverBudget => _monthlyBudget > 0 && _totalSpent > _monthlyBudget;
  bool get hasBudgetSet => _monthlyBudget > 0;
  bool get isLoading => _isLoading;

  List<CategoryBudgetStatus> get categoryStatuses => _categoryStatuses;

  BudgetThreshold get currentThreshold {
    if (_monthlyBudget <= 0) return BudgetThreshold.safe;
    if (_totalSpent > _monthlyBudget) return BudgetThreshold.exceeded;
    final pct = usedPercentage;
    if (pct >= 90) return BudgetThreshold.critical;
    if (pct >= 75) return BudgetThreshold.warning;
    if (pct >= 50) return BudgetThreshold.half;
    return BudgetThreshold.safe;
  }

  String? warningMessage(String Function(double) formatAmount) {
    if (_monthlyBudget <= 0) return null;
    final pct = usedPercentage;

    if (pct > 100) {
      return 'Budget exceeded by ${formatAmount(exceededAmount)}.';
    } else if (pct >= 100) {
      return 'You have used 100% of your monthly budget.';
    } else if (pct >= 90) {
      return 'Warning: You have used ${pct.toStringAsFixed(1)}% of your monthly budget.';
    } else if (pct >= 75) {
      return 'Attention: You have used ${pct.toStringAsFixed(1)}% of your monthly budget.';
    } else if (pct >= 50) {
      return 'Notice: You have used ${pct.toStringAsFixed(1)}% of your monthly budget.';
    }
    return null;
  }

  Future<void> computeMonthlyBudget(int month, int year) async {
    _isLoading = true;
    notifyListeners();

    try {
      _monthlyBudget = await _budgetRepo.getMonthlyBudget(month, year);
      _totalSpent = await _budgetRepo.getMonthTotalExpenses(month, year);
      final limits = await _budgetRepo.getCategoryBudgets(month, year);
      final spend = await _budgetRepo.getCategorySpend(month, year);
      _categoryStatuses = limits.entries
          .map((e) => CategoryBudgetStatus(e.key, e.value, spend[e.key] ?? 0.0))
          .toList()
        ..sort((a, b) => b.pct.compareTo(a.pct));
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setMonthlyBudget(double amount, int month, int year) async {
    _monthlyBudget = amount;
    await _budgetRepo.setMonthlyBudget(amount: amount, month: month, year: year);
    await computeMonthlyBudget(month, year);
  }

  Future<void> setCategoryBudget(String category, double amount) async {
    final now = DateTime.now();
    await _budgetRepo.setCategoryBudget(
      category: category,
      amount: amount,
      month: now.month,
      year: now.year,
    );
    await computeMonthlyBudget(now.month, now.year);
  }
}