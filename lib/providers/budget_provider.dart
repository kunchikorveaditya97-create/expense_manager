// lib/providers/budget_provider.dart
import 'package:flutter/foundation.dart';
import '../data/repositories/budget_repository.dart';

enum BudgetThreshold {
  safe,        // < 50%
  half,        // >= 50% & < 75%
  warning,     // >= 75% & < 90%
  critical,    // >= 90% & <= 100%
  exceeded,    // > 100%
}

class BudgetProvider extends ChangeNotifier {
  final IBudgetRepository _budgetRepo;

  double _monthlyBudget = 0.0;
  double _totalSpent = 0.0;
  bool _isLoading = false;

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

  BudgetThreshold get currentThreshold {
    if (_monthlyBudget <= 0) return BudgetThreshold.safe;
    if (_totalSpent > _monthlyBudget) return BudgetThreshold.exceeded;
    final pct = usedPercentage;
    if (pct >= 90) return BudgetThreshold.critical;
    if (pct >= 75) return BudgetThreshold.warning;
    if (pct >= 50) return BudgetThreshold.half;
    return BudgetThreshold.safe;
  }

  String? get warningMessage {
    if (_monthlyBudget <= 0) return null;
    final pct = usedPercentage;

    if (pct > 100) {
      return 'Budget exceeded by ₹${exceededAmount.toStringAsFixed(2)}.';
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
    } catch (_) {
      // Fallback
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
}