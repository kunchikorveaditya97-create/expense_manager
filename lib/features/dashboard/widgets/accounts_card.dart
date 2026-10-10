import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/currency_provider.dart';
import '../../../providers/transaction_provider.dart';

class AccountsCard extends StatelessWidget {
  const AccountsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final txn = context.watch<TransactionProvider>();
    final currency = context.watch<CurrencyProvider>();
    final accounts = txn.accounts;

    if (accounts.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accounts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final a in accounts)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(a.name),
                trailing: Text(
                  currency.format(txn.balanceFor(a.id)),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}