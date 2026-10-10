import 'package:expense_manager/data/repositories/budget_repository.dart';
import 'package:expense_manager/providers/budget_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory budget repository. Only the methods BudgetProvider calls are
/// implemented; anything else throws via noSuchMethod.
class FakeBudgetRepository implements IBudgetRepository {
  FakeBudgetRepository({
    this.monthly = 0,
    this.spent = 0,
    Map<String, double>? limits,
    Map<String, double>? spend,
  })  : limits = {...?limits},
        spend = {...?spend};

  double monthly;
  double spent;
  final Map<String, double> limits;
  final Map<String, double> spend;
  bool shouldThrow = false;
  double? lastMonthlySet;

  @override
  Future<double> getMonthlyBudget(int month, int year) async {
    if (shouldThrow) throw Exception('db unavailable');
    return monthly;
  }

  @override
  Future<double> getMonthTotalExpenses(int month, int year) async => spent;

  @override
  Future<Map<String, double>> getCategoryBudgets(int month, int year) async =>
      limits;

  @override
  Future<Map<String, double>> getCategorySpend(int month, int year) async =>
      spend;

  @override
  Future<void> setMonthlyBudget({
    required double amount,
    required int month,
    required int year,
  }) async {
    lastMonthlySet = amount;
    monthly = amount;
  }

  @override
  Future<void> setCategoryBudget({
    required String category,
    required double amount,
    required int month,
    required int year,
  }) async {
    limits[category] = amount;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String fmt(double v) => '\$${v.toStringAsFixed(0)}';

Future<BudgetProvider> load(FakeBudgetRepository repo) async {
  final p = BudgetProvider(repo);
  await pumpEventQueue(); // constructor starts an async load
  return p;
}

void main() {
  group('monthly budget numbers', () {
    test('Budget 2000 / Spent 1450 -> Remaining 550, Used 72.5%', () async {
      final p = await load(FakeBudgetRepository(monthly: 2000, spent: 1450));

      expect(p.monthlyBudget, 2000);
      expect(p.totalSpent, 1450);
      expect(p.remaining, 550);
      expect(p.usedPercentage, closeTo(72.5, 0.001));
      expect(p.isOverBudget, isFalse);
    });

    test('over budget: remaining clamps to 0 and exceeded amount is reported',
            () async {
          final p = await load(FakeBudgetRepository(monthly: 1000, spent: 1125));

          expect(p.remaining, 0);
          expect(p.exceededAmount, 125);
          expect(p.isOverBudget, isTrue);
          expect(p.progressRatio, 1.0); // bar never overflows
        });

    test('no budget set: everything is zero and safe', () async {
      final p = await load(FakeBudgetRepository(monthly: 0, spent: 300));

      expect(p.hasBudgetSet, isFalse);
      expect(p.usedPercentage, 0);
      expect(p.currentThreshold, BudgetThreshold.safe);
      expect(p.warningMessage(fmt), isNull);
      expect(p.isOverBudget, isFalse);
    });
  });

  group('warning thresholds (50 / 75 / 90 / 100)', () {
    final cases = <double, BudgetThreshold>{
      0: BudgetThreshold.safe,
      499: BudgetThreshold.safe,
      500: BudgetThreshold.half,
      749: BudgetThreshold.half,
      750: BudgetThreshold.warning,
      899: BudgetThreshold.warning,
      900: BudgetThreshold.critical,
      1000: BudgetThreshold.critical, // exactly 100% is not "exceeded"
      1001: BudgetThreshold.exceeded,
    };

    cases.forEach((spent, expected) {
      test('spent $spent of 1000 -> $expected', () async {
        final p =
        await load(FakeBudgetRepository(monthly: 1000, spent: spent));
        expect(p.currentThreshold, expected);
      });
    });
  });

  group('warning messages', () {
    Future<String?> msg(double spent) async {
      final p = await load(FakeBudgetRepository(monthly: 1000, spent: spent));
      return p.warningMessage(fmt);
    }

    test('no message below 50%', () async {
      expect(await msg(499), isNull);
    });

    test('50% notice', () async {
      expect(await msg(500),
          'Notice: You have used 50.0% of your monthly budget.');
    });

    test('75% attention', () async {
      expect(await msg(750),
          'Attention: You have used 75.0% of your monthly budget.');
    });

    test('90% warning', () async {
      expect(await msg(900),
          'Warning: You have used 90.0% of your monthly budget.');
    });

    test('exactly 100%', () async {
      expect(await msg(1000), 'You have used 100% of your monthly budget.');
    });

    test('exceeded message shows the overspend', () async {
      expect(await msg(1125), 'Budget exceeded by \$125.');
    });
  });

  group('category budgets', () {
    test('statuses are calculated per category and sorted by usage', () async {
      final p = await load(FakeBudgetRepository(
        monthly: 2000,
        spent: 250,
        limits: {'Food': 400, 'Travel': 150},
        spend: {'Food': 100, 'Travel': 150},
      ));

      expect(p.categoryStatuses.map((s) => s.category), ['Travel', 'Food']);

      final travel = p.categoryStatuses.first;
      expect(travel.pct, 100);
      expect(travel.exceeded, isFalse); // exactly at limit
      expect(travel.remaining, 0);

      final food = p.categoryStatuses.last;
      expect(food.pct, 25);
      expect(food.remaining, 300);
    });

    test('category with no spending reads as 0%', () async {
      final p = await load(FakeBudgetRepository(
        monthly: 1000,
        limits: {'Health': 200},
      ));

      expect(p.categoryStatuses.single.spent, 0);
      expect(p.categoryStatuses.single.pct, 0);
    });

    test('overspent category is flagged and ratio is clamped', () async {
      final p = await load(FakeBudgetRepository(
        monthly: 1000,
        limits: {'Food': 100},
        spend: {'Food': 160},
      ));

      final s = p.categoryStatuses.single;
      expect(s.exceeded, isTrue);
      expect(s.remaining, -60);
      expect(s.ratio, 1.0);
    });

    test('setCategoryBudget saves and refreshes the list', () async {
      final repo = FakeBudgetRepository(monthly: 1000);
      final p = await load(repo);
      expect(p.categoryStatuses, isEmpty);

      await p.setCategoryBudget('Food', 400);

      expect(p.categoryStatuses.single.category, 'Food');
      expect(p.categoryStatuses.single.limit, 400);
    });
  });

  group('updating and errors', () {
    test('setMonthlyBudget saves to the repository and recomputes', () async {
      final repo = FakeBudgetRepository(monthly: 1000, spent: 500);
      final p = await load(repo);

      await p.setMonthlyBudget(2000, 10, 2026);

      expect(repo.lastMonthlySet, 2000);
      expect(p.monthlyBudget, 2000);
      expect(p.usedPercentage, closeTo(25, 0.001));
    });

    test('a repository failure does not crash and clears the loading flag',
            () async {
          final repo = FakeBudgetRepository(monthly: 1000)..shouldThrow = true;
          final p = await load(repo);

          expect(p.isLoading, isFalse);
          expect(p.monthlyBudget, 0);
        });

    test('notifies listeners when loading finishes', () async {
      final repo = FakeBudgetRepository(monthly: 1000, spent: 100);
      final p = await load(repo);
      var notified = 0;
      p.addListener(() => notified++);

      await p.computeMonthlyBudget(10, 2026);

      expect(notified, greaterThanOrEqualTo(2)); // loading on, loading off
    });
  });
}