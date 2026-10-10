// lib/features/budget/budget_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';

class MonthlyBudgetCard extends StatelessWidget {
  const MonthlyBudgetCard({super.key});

  Color _getStatusColor(BudgetThreshold threshold, BuildContext context) {
    switch (threshold) {
      case BudgetThreshold.exceeded:
        return Colors.red.shade700;
      case BudgetThreshold.critical:
        return Colors.deepOrange;
      case BudgetThreshold.warning:
        return Colors.amber.shade800;
      case BudgetThreshold.half:
        return Colors.blue;
      case BudgetThreshold.safe:
        return Colors.teal;
    }
  }

  void _showConfigureBudgetDialog(BuildContext context, BudgetProvider budgetProvider) {
    final controller = TextEditingController(
      text: budgetProvider.monthlyBudget > 0
          ? budgetProvider.monthlyBudget.toStringAsFixed(0)
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configure Monthly Budget'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Budget Amount',
            prefixText: '${context.read<CurrencyProvider>().current.symbol} ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(controller.text) ?? 0.0;
              final now = DateTime.now();
              budgetProvider.setMonthlyBudget(amount, now.month, now.year);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budgetProvider = context.watch<BudgetProvider>();
    final currency = context.watch<CurrencyProvider>();
    final threshold = budgetProvider.currentThreshold;
    final statusColor = _getStatusColor(threshold, context);
    final warning = budgetProvider.warningMessage(currency.format);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.pie_chart_outline, color: statusColor),
                    const SizedBox(width: 8),
                    const Text(
                      'Monthly Budget',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Set Budget',
                  onPressed: () => _showConfigureBudgetDialog(context, budgetProvider),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!budgetProvider.hasBudgetSet) ...[
              Text(
                'No budget defined for this month.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showConfigureBudgetDialog(context, budgetProvider),
                icon: const Icon(Icons.add),
                label: const Text('Set Monthly Budget'),
              ),
            ] else ...[
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: budgetProvider.progressRatio,
                  minHeight: 12,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              const SizedBox(height: 14),

              // Summary Breakdown
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _metricTile('Budget', currency.format(budgetProvider.monthlyBudget)),
                  _metricTile('Spent', currency.format(budgetProvider.totalSpent)),
                  _metricTile(
                    budgetProvider.isOverBudget ? 'Over Budget' : 'Remaining',
                    budgetProvider.isOverBudget
                        ? currency.format(budgetProvider.exceededAmount)
                        : currency.format(budgetProvider.remaining),
                    color: budgetProvider.isOverBudget ? Colors.red.shade700 : null,
                  ),
                  _metricTile(
                    'Used',
                    '${budgetProvider.usedPercentage.toStringAsFixed(1)}%',
                    color: statusColor,
                  ),
                ],
              ),

              // Threshold Milestone Alerts
              if (warning != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}