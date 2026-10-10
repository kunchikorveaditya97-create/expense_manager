import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/goal_icons.dart';
import '../../data/local/app_database.dart';
import '../../providers/currency_provider.dart';
import '../../providers/goal_provider.dart';

double goalProgress(SavingsGoal g) =>
    g.targetAmount > 0 ? (g.currentAmount / g.targetAmount) : 0.0;

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalProvider>().goals;
    final cur = context.watch<CurrencyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showGoalDialog(context, null),
        child: const Icon(Icons.add),
      ),
      body: goals.isEmpty
          ? const Center(
          child: Text('No goals yet.\nTap + to create one.',
              textAlign: TextAlign.center))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [for (final g in goals) _tile(context, g, cur)],
      ),
    );
  }

  Widget _tile(BuildContext context, SavingsGoal g, CurrencyProvider cur) {
    final p = goalProgress(g);
    final reached = g.currentAmount >= g.targetAmount;
    final daysLeft = g.targetDate
        .difference(DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day))
        .inDays;
    final when = reached
        ? 'Goal reached'
        : daysLeft < 0
        ? 'Past target date (${DateFormat.yMMMd().format(g.targetDate)})'
        : '${DateFormat.yMMMd().format(g.targetDate)} · $daysLeft days left';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(goalIcon(g.iconName))),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(g.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _onMenu(context, v, g),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Add funds')),
                    PopupMenuItem(value: 'withdraw', child: Text('Withdraw')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: p.clamp(0.0, 1.0).toDouble(),
                minHeight: 10,
                valueColor: AlwaysStoppedAnimation(
                    reached ? Colors.green : Colors.teal),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${cur.format(g.currentAmount)} of ${cur.format(g.targetAmount)} · ${(p * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Text(when, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String v, SavingsGoal g) async {
    switch (v) {
      case 'add':
        return _amountDialog(context, g, add: true);
      case 'withdraw':
        return _amountDialog(context, g, add: false);
      case 'edit':
        return showGoalDialog(context, g);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${g.name}?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true && context.mounted) {
          await context.read<GoalProvider>().delete(g.id);
        }
    }
  }

  Future<void> _amountDialog(BuildContext context, SavingsGoal g,
      {required bool add}) async {
    final gp = context.read<GoalProvider>();
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(add ? 'Add to ${g.name}' : 'Withdraw from ${g.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '${context.read<CurrencyProvider>().current.symbol} ',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final v = double.tryParse(ctrl.text.trim()) ?? 0;
              if (v <= 0) return;
              await gp.addFunds(g.id, add ? v : -v);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(add ? 'Add' : 'Withdraw'),
          ),
        ],
      ),
    );
  }
}

Future<void> showGoalDialog(BuildContext context, SavingsGoal? existing) async {
  final gp = context.read<GoalProvider>();
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final targetCtrl = TextEditingController(
      text: existing != null ? existing.targetAmount.toStringAsFixed(0) : '');
  final savedCtrl = TextEditingController(text: '0');
  DateTime date =
      existing?.targetDate ?? DateTime.now().add(const Duration(days: 90));
  String icon = existing?.iconName ?? 'savings';
  String? error;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(existing == null ? 'New Savings Goal' : 'Edit Goal'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration:
                InputDecoration(labelText: 'Goal name', errorText: error),
              ),
              TextField(
                controller: targetCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Target amount'),
              ),
              if (existing == null)
                TextField(
                  controller: savedCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Already saved'),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Target date'),
                subtitle: Text(DateFormat.yMMMd().format(date)),
                onTap: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setLocal(() => date = p);
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in goalIcons.entries)
                    ChoiceChip(
                      label: Icon(e.value, size: 20),
                      selected: icon == e.key,
                      onSelected: (_) => setLocal(() => icon = e.key),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final target = double.tryParse(targetCtrl.text.trim()) ?? 0;
              if (name.isEmpty) {
                setLocal(() => error = 'Enter a goal name');
                return;
              }
              if (target <= 0) {
                setLocal(() => error = 'Enter a target amount');
                return;
              }
              if (existing == null) {
                final saved = double.tryParse(savedCtrl.text.trim()) ?? 0;
                await gp.add(name, target, saved < 0 ? 0 : saved, date, icon);
              } else {
                await gp.update(existing.id, name, target, date, icon);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}