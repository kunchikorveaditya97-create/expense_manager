import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/tables.dart';
import '../../providers/transaction_provider.dart';
import 'add_edit_transaction_screen.dart';
import '../../providers/currency_provider.dart';
import 'widgets/filter_sheet.dart';
import '../../providers/category_provider.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<TransactionProvider>().setSearch(value);
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<TransactionProvider>().fetchMore();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final currency = context.watch<CurrencyProvider>();
    final txns = provider.transactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(provider.hasActiveFilters
                ? Icons.filter_alt
                : Icons.filter_list),
            onPressed: () => _openFilterModal(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search note, category or amount',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28)),
              ),
            ),
          ),
        ),
      ),
      body: txns.isEmpty && !provider.isLoading
          ? const Center(child: Text('No transactions found.'))
          : ListView.builder(
        controller: _scrollController,
        itemCount: txns.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == txns.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final item = txns[index];
          final isExpense = item.type == TransactionType.expense;

          return Slidable(
            key: ValueKey(item.id),
            startActionPane: ActionPane(
              motion: const DrawerMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddEditTransactionScreen(transaction: item),
                      ),
                    );
                  },
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  icon: Icons.edit,
                  label: 'Edit',
                ),
              ],
            ),
            endActionPane: ActionPane(
              motion: const DrawerMotion(),
              children: [
                SlidableAction(
                  onPressed: (_) {
                    final messenger = ScaffoldMessenger.of(context);
                    provider.deleteTransaction(item.id);

                    messenger.clearSnackBars();

                    final controller = messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Transaction deleted'),
                        duration: const Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            provider.restoreTransaction(item.id);
                            messenger.hideCurrentSnackBar();
                          },
                        ),
                      ),
                    );

                    Timer(const Duration(seconds: 3), () {
                      controller.close();
                    });
                  },
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  icon: Icons.delete,
                  label: 'Delete',
                ),
              ],
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                isExpense ? Colors.red.shade50 : Colors.green.shade50,
                child: Icon(
                  context.watch<CategoryProvider>().iconFor(item.categoryId),
                  color: isExpense ? Colors.red : Colors.green,
                ),
              ),
              title: Text(
                item.note?.isNotEmpty == true ? item.note! : item.categoryId,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${context.watch<TransactionProvider>().accountName(item.accountId)} • ${DateFormat.yMMMd().format(item.transactionDate)}',
              ),
              trailing: Text(
                '${isExpense ? '-' : '+'}${currency.format(item.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isExpense ? Colors.red : Colors.green,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFilterModal(BuildContext context) {
    final provider = context.read<TransactionProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const FilterSheet(),
      ),
    );
  }
}