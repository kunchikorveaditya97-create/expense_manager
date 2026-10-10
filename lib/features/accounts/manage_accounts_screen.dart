import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/app_database.dart';
import '../../providers/account_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/transaction_provider.dart';

const _accountTypes = {
  'cash': 'Cash',
  'bank_account': 'Bank Account',
  'credit_card': 'Credit Card',
  'wallet': 'Wallet',
  'savings': 'Savings Account',
};

class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final txn = context.watch<TransactionProvider>();
    final currency = context.watch<CurrencyProvider>();
    final accounts = txn.accounts;
    final combined =
    accounts.fold<double>(0, (s, a) => s + txn.balanceFor(a.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAccountDialog(context, accounts),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              title: const Text('Combined balance'),
              trailing: Text(
                currency.format(combined),
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          for (final a in accounts)
            ListTile(
              leading: const CircleAvatar(
                  child: Icon(Icons.account_balance_wallet_outlined)),
              title: Text(a.name),
              subtitle: Text(_accountTypes[a.type] ?? a.type),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currency.format(txn.balanceFor(a.id)),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, a),
                  ),
                ],
              ),
              onTap: () =>
                  _showAccountDialog(context, accounts, existing: a),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${a.name}?'),
        content: const Text(
            'Only accounts with no transactions can be deleted.'),
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
    if (ok != true || !context.mounted) return;

    final deleted = await context.read<AccountProvider>().deleteIfUnused(a.id);
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This account has transactions and cannot be deleted.')),
      );
    }
  }

  Future<void> _showAccountDialog(
      BuildContext context,
      List<Account> accounts, {
        Account? existing,
      }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balCtrl = TextEditingController(
        text: existing != null ? existing.initialBalance.toString() : '0');
    String type = existing?.type ?? 'cash';
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add Account' : 'Edit Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration:
                InputDecoration(labelText: 'Name', errorText: error),
              ),
              if (existing == null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: _accountTypes.entries
                      .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: balCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Opening balance'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setLocal(() => error = 'Enter a name');
                  return;
                }
                final dup = accounts.any((a) =>
                a.name.toLowerCase() == name.toLowerCase() &&
                    a.id != existing?.id);
                if (dup) {
                  setLocal(() => error = 'An account with this name exists');
                  return;
                }
                final bal = double.tryParse(balCtrl.text.trim()) ?? 0;
                final ap = context.read<AccountProvider>();
                if (existing == null) {
                  await ap.add(name, type, bal);
                } else {
                  await ap.update(existing.id, name, bal);
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
}