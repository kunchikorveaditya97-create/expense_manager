import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/currency_provider.dart';
import '../../providers/goal_provider.dart';
import 'goals_screen.dart';

class GoalsCard extends StatelessWidget {
  const GoalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalProvider>().goals.take(3).toList();
    final cur = context.watch<CurrencyProvider>();

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
                const Icon(Icons.savings_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Savings Goals',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GoalsScreen())),
                  child: Text(goals.isEmpty ? 'Add' : 'View all'),
                ),
              ],
            ),
            if (goals.isEmpty)
              Text('No savings goals yet.',
                  style: TextStyle(color: Colors.grey.shade600))
            else
              for (final g in goals) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: Text(g.name,
                            style:
                            const TextStyle(fontWeight: FontWeight.w500))),
                    Text(
                      '${cur.format(g.currentAmount)} / ${cur.format(g.targetAmount)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: goalProgress(g).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}