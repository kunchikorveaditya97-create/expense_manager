import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:expense_manager/features/budget/budget_card.dart';
import 'package:expense_manager/providers/currency_provider.dart';
import 'package:expense_manager/providers/budget_provider.dart';
import 'package:expense_manager/providers/transaction_provider.dart';
import 'package:expense_manager/sync/sync_provider.dart';
import 'widgets/sync_status_badge.dart';
import 'widgets/recent_transactions_card.dart';
import 'widgets/insights_card.dart';
import 'package:intl/intl.dart';
import 'widgets/accounts_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  @override
  Widget build(BuildContext context) {
    final txnProvider = context.watch<TransactionProvider>();
    final budgetProvider = context.watch<BudgetProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final currency = context.watch<CurrencyProvider>();

    final balance = txnProvider.totalBalance;
    final income = txnProvider.monthIncome;
    final expense = txnProvider.monthExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Manager'),
        actions: [
          const Center(
            child: SyncStatusBadge(),
          ),
          IconButton(
            tooltip: 'Sync Changes',
            icon: syncProvider.isSyncing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.sync),
            onPressed: syncProvider.isSyncing
                ? null
                : () async {
              await syncProvider.syncAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync completed')),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final now = DateTime.now();
          await budgetProvider.computeMonthlyBudget(now.month, now.year);
          if (syncProvider.pendingCount > 0) {
            await syncProvider.syncAll();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 3,
                margin: const EdgeInsets.all(16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Balance',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        currency.format(balance),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 32),
                      Text(
                        'This month · ${DateFormat('MMMM yyyy').format(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildCashFlowTile(
                            context: context,
                            label: 'Income',
                            amount: income,
                            color: Colors.green.shade600,
                            icon: Icons.arrow_downward_rounded,
                          ),
                          _buildCashFlowTile(
                            context: context,
                            label: 'Expense',
                            amount: expense,
                            color: Colors.red.shade600,
                            icon: Icons.arrow_upward_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const MonthlyBudgetCard(),
              const AccountsCard(),
              const InsightsCard(),
              const RecentTransactionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCashFlowTile({
    required BuildContext context,
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              context.watch<CurrencyProvider>().format(amount),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}