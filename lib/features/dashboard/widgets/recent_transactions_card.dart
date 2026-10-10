// lib/features/dashboard/widgets/recent_transactions_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/local/app_database.dart';
import '../../../data/local/tables.dart';
import '../../../providers/currency_provider.dart';
import '../../../providers/transaction_provider.dart';

class RecentTransactionsCard extends StatelessWidget {
  const RecentTransactionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Watching makes this card reload whenever transactions change
    context.watch<TransactionProvider>();
    final currency = context.watch<CurrencyProvider>();
    final db = context.read<AppDatabase>();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Transactions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Transaction>>(
              future: db.getRecentTransactions(),
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (items == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No transactions yet. Tap + to add one.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                return Column(
                  children: items.map((t) {
                    final isExpense = t.type == TransactionType.expense;
                    final color =
                    isExpense ? Colors.red.shade600 : Colors.green.shade600;
                    final date = DateFormat('dd MMM yyyy')
                        .format(t.transactionDate.toLocal());
                    final note = (t.note ?? '').trim();

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(
                          isExpense
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: color,
                        ),
                      ),
                      title: Text(t.categoryId),
                      subtitle: Text(note.isEmpty ? date : '$date · $note'),
                      trailing: Text(
                        '${isExpense ? '-' : '+'}${currency.format(t.amount)}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}