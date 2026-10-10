// lib/features/analytics/analytics_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../../providers/transaction_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _touchedIndex = -1;
  final currencyFormat = NumberFormat.simpleCurrency();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txns = context.watch<TransactionProvider>().transactions;
    final expenses = txns.where((t) => t.type == TransactionType.expense && t.deletedAt == null).toList();

    // Group expenses by category
    final Map<String, double> categoryTotals = {};
    for (final e in expenses) {
      categoryTotals[e.categoryId] = (categoryTotals[e.categoryId] ?? 0.0) + e.amount;
    }

    final double totalExpense = categoryTotals.values.fold(0.0, (sum, val) => sum + val);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics & Trends', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: expenses.isEmpty
          ? const Center(child: Text('No expense data available for charts.'))
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Category Breakdown', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // 1. Donut Chart Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 46,
                        sections: _generateChartSections(categoryTotals, totalExpense),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Legend List
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: categoryTotals.keys.map((cat) {
                      final color = _getCategoryColor(cat);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text(cat, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      );
                    }).toList(),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 2. Itemized Breakdown List
          Text('Spending by Category', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categoryTotals.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final category = categoryTotals.keys.elementAt(index);
                final amount = categoryTotals[category]!;
                final percentage = (totalExpense > 0) ? (amount / totalExpense) * 100 : 0.0;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getCategoryColor(category).withOpacity(0.2),
                    child: Icon(Icons.circle, color: _getCategoryColor(category), size: 16),
                  ),
                  title: Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${percentage.toStringAsFixed(1)}% of total'),
                  trailing: Text(
                    currencyFormat.format(amount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  List<PieChartSectionData> _generateChartSections(Map<String, double> totals, double grandTotal) {
    int i = 0;
    return totals.entries.map((entry) {
      final isTouched = i == _touchedIndex;
      final fontSize = isTouched ? 16.0 : 12.0;
      final radius = isTouched ? 58.0 : 50.0;
      final percentage = (entry.value / grandTotal) * 100;
      final color = _getCategoryColor(entry.key);
      i++;

      return PieChartSectionData(
        color: color,
        value: entry.value,
        title: '${percentage.toStringAsFixed(0)}%',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 2)],
        ),
      );
    }).toList();
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Colors.orangeAccent;
      case 'travel':
        return Colors.blueAccent;
      case 'shopping':
        return Colors.purpleAccent;
      case 'bills':
      case 'rent':
        return Colors.teal;
      case 'entertainment':
        return Colors.pinkAccent;
      case 'health':
        return Colors.redAccent;
      default:
        return Colors.indigoAccent;
    }
  }
}