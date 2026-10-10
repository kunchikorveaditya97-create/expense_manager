import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/currency_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _touchedIndex = -1;

  static const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final a = context.watch<AnalyticsProvider>();
    final hasData = a.income > 0 || a.expense > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics & Trends',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<AnalyticsPeriod>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: AnalyticsPeriod.week, label: Text('Week')),
              ButtonSegment(value: AnalyticsPeriod.month, label: Text('Month')),
              ButtonSegment(
                  value: AnalyticsPeriod.threeMonths, label: Text('3 Months')),
              ButtonSegment(value: AnalyticsPeriod.year, label: Text('Year')),
            ],
            selected: {a.period},
            onSelectionChanged: (s) =>
                context.read<AnalyticsProvider>().setPeriod(s.first),
          ),
          const SizedBox(height: 16),
          _summaryRow(a, currency),
          if (!hasData)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: Text('No data for this period.')),
            )
          else ...[
            _card('Income vs Expenses', _incomeVsExpense(a)),
            _card('Spending Trend', _trendChart(a)),
            if (a.categoryTotals.isNotEmpty) ...[
              _card('Category Breakdown', _pie(a)),
              _card('Spending by Category', _categoryList(a, currency)),
            ],
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _summaryRow(AnalyticsProvider a, CurrencyProvider c) {
    Widget tile(String label, double v, Color color) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  c.format(v),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(children: [
      tile('Income', a.income, Colors.green),
      tile('Expenses', a.expense, Colors.red),
      tile('Net savings', a.netSavings,
          a.netSavings >= 0 ? Colors.green : Colors.red),
    ]);
  }

  Widget _card(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _incomeVsExpense(AnalyticsProvider a) {
    final maxY = (a.income > a.expense ? a.income : a.expense) * 1.2;
    BarChartGroupData group(int x, double v, Color c) => BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: v,
          color: c,
          width: 36,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceEvenly,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: _noTitles,
            topTitles: _noTitles,
            rightTitles: _noTitles,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(v.toInt() == 0 ? 'Income' : 'Expenses'),
                ),
              ),
            ),
          ),
          barGroups: [
            group(0, a.income, Colors.green),
            group(1, a.expense, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _trendChart(AnalyticsProvider a) {
    final t = a.trend;
    final maxV = t.fold<double>(0, (m, p) => p.expense > m ? p.expense : m);
    final interval = (t.length / 6).ceilToDouble().clamp(1, 100).toDouble();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxV == 0 ? 1 : maxV * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: _noTitles,
            topTitles: _noTitles,
            rightTitles: _noTitles,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: interval,
                reservedSize: 28,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= t.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(t[i].label, style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < t.length; i++)
                  FlSpot(i.toDouble(), t[i].expense),
              ],
              isCurved: true,
              barWidth: 3,
              color: Colors.redAccent,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.redAccent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pie(AnalyticsProvider a) {
    final totals = a.categoryTotals;
    int i = 0;
    final sections = totals.entries.map((e) {
      final touched = i == _touchedIndex;
      i++;
      return PieChartSectionData(
        color: _getCategoryColor(e.key),
        value: e.value,
        title: '${(e.value / a.expense * 100).toStringAsFixed(0)}%',
        radius: touched ? 58 : 50,
        titleStyle: TextStyle(
          fontSize: touched ? 16 : 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 2)],
        ),
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response?.touchedSection == null) {
                      _touchedIndex = -1;
                      return;
                    }
                    _touchedIndex = response!.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 46,
              sections: sections,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: totals.keys.map((cat) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: _getCategoryColor(cat), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(cat,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _categoryList(AnalyticsProvider a, CurrencyProvider currency) {
    return Column(
      children: a.categoryTotals.entries.map((e) {
        final pct = a.expense > 0 ? e.value / a.expense * 100 : 0.0;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: _getCategoryColor(e.key).withValues(alpha: 0.2),
            child: Icon(Icons.circle, color: _getCategoryColor(e.key), size: 16),
          ),
          title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${pct.toStringAsFixed(1)}% of total'),
          trailing: Text(
            currency.format(e.value),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        );
      }).toList(),
    );
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
      case 'education':
        return Colors.amber;
      case 'subscription':
        return Colors.cyan;
      default:
        return Colors.indigoAccent;
    }
  }
}