import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/tables.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/currency_provider.dart';

Color budgetStatusColor(double pct) {
  if (pct > 100) return Colors.red.shade700;
  if (pct >= 90) return Colors.deepOrange;
  if (pct >= 75) return Colors.amber.shade800;
  if (pct >= 50) return Colors.blue;
  return Colors.teal;
}

class CategoryBudgetsScreen extends StatelessWidget {
  const CategoryBudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BudgetProvider>();
    final cur = context.watch<CurrencyProvider>();
    final cats = context.watch<CategoryProvider>();
    final list = bp.categoryStatuses;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Category Budgets · ${DateFormat('MMMM').format(DateTime.now())}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, null),
        child: const Icon(Icons.add),
      ),
      body: list.isEmpty
          ? const Center(
        child: Text('No category budgets yet.\nTap + to add one.',
            textAlign: TextAlign.center),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in list)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: InkWell(
                  onTap: () => _showDialog(context, s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(cats.iconFor(s.category), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.category,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                bp.setCategoryBudget(s.category, 0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: s.ratio,
                          minHeight: 10,
                          backgroundColor: budgetStatusColor(s.pct)
                              .withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(
                              budgetStatusColor(s.pct)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.exceeded
                            ? '${cur.format(s.spent)} of ${cur.format(s.limit)} · exceeded by ${cur.format(-s.remaining)}'
                            : '${cur.format(s.spent)} of ${cur.format(s.limit)} · ${s.pct.toStringAsFixed(0)}% used',
                        style: TextStyle(
                            fontSize: 12,
                            color: budgetStatusColor(s.pct)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDialog(
      BuildContext context, CategoryBudgetStatus? existing) async {
    final bp = context.read<BudgetProvider>();
    final available = context
        .read<CategoryProvider>()
        .activeNames(TransactionType.expense)
        .where((c) => !bp.categoryStatuses.any((s) => s.category == c))
        .toList();

    final items = existing != null ? [existing.category] : available;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every category already has a budget.')),
      );
      return;
    }

    String selected = items.first;
    final ctrl = TextEditingController(
        text: existing != null ? existing.limit.toStringAsFixed(0) : '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New Category Budget' : 'Edit Budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Category'),
                items: items
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: existing != null
                    ? null
                    : (v) => setLocal(() => selected = v ?? selected),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monthly limit',
                  prefixText:
                  '${context.read<CurrencyProvider>().current.symbol} ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(ctrl.text.trim()) ?? 0;
                if (amount <= 0) return;
                await bp.setCategoryBudget(selected, amount);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}