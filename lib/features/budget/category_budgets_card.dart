import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import 'category_budgets_screen.dart';

class CategoryBudgetsCard extends StatelessWidget {
  const CategoryBudgetsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BudgetProvider>();
    final cur = context.watch<CurrencyProvider>();
    final top = bp.categoryStatuses.take(3).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.donut_small_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Category Budgets',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CategoryBudgetsScreen()),
                  ),
                  child: Text(top.isEmpty ? 'Add' : 'Manage'),
                ),
              ],
            ),
            if (top.isEmpty)
              Text('No category budgets set.',
                  style: TextStyle(color: Colors.grey.shade600))
            else
              for (final s in top) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: Text(s.category,
                            style: const TextStyle(fontWeight: FontWeight.w500))),
                    Text(
                      '${cur.format(s.spent)} / ${cur.format(s.limit)}',
                      style: TextStyle(
                          fontSize: 12, color: budgetStatusColor(s.pct)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: s.ratio,
                    minHeight: 8,
                    backgroundColor:
                    budgetStatusColor(s.pct).withValues(alpha: 0.15),
                    valueColor:
                    AlwaysStoppedAnimation(budgetStatusColor(s.pct)),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}