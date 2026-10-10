import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../providers/category_provider.dart';
import '../../../data/local/tables.dart';
import '../../../providers/transaction_provider.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  TransactionType? _type;
  String? _category;
  String? _account;
  DateTimeRange? _range;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = context.read<TransactionProvider>();
    _type = p.filterType;
    _category = p.filterCategoryId;
    _account = p.filterAccountId;
    if (p.filterStart != null && p.filterEnd != null) {
      _range = DateTimeRange(start: p.filterStart!, end: p.filterEnd!);
    }
    _minCtrl.text = p.filterMin?.toString() ?? '';
    _maxCtrl.text = p.filterMax?.toString() ?? '';
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _thisMonth() {
    final now = DateTime.now();
    setState(() {
      _range = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
    });
  }

  void _apply() {
    final r = _range;
    context.read<TransactionProvider>().setFilters(
      type: _type,
      categoryId: _category,
      accountId: _account,
      startDate: r == null
          ? null
          : DateTime(r.start.year, r.start.month, r.start.day),
      endDate: r == null
          ? null
          : DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59),
      minAmount: double.tryParse(_minCtrl.text.trim()),
      maxAmount: double.tryParse(_maxCtrl.text.trim()),
    );
    Navigator.pop(context);
  }

  void _clear() {
    context.read<TransactionProvider>().clearFilters();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.read<TransactionProvider>().accounts;
    final fmt = DateFormat.yMMMd();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Filter Transactions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TransactionType?>(
            value: _type,
            decoration: const InputDecoration(
                labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(
                  value: TransactionType.expense, child: Text('Expense')),
              DropdownMenuItem(
                  value: TransactionType.income, child: Text('Income')),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _category,
            decoration: const InputDecoration(
                labelText: 'Category', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ...context.read<CategoryProvider>().allNames
                  .map((c) => DropdownMenuItem(value: c, child: Text(c))),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _account,
            decoration: const InputDecoration(
                labelText: 'Account', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ...accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))),
            ],
            onChanged: (v) => setState(() => _account = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            leading: const Icon(Icons.date_range),
            title: Text(_range == null
                ? 'Any date'
                : '${fmt.format(_range!.start)} - ${fmt.format(_range!.end)}'),
            trailing: _range == null
                ? null
                : IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _range = null),
            ),
            onTap: _pickRange,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: _thisMonth, child: const Text('This month')),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Min amount', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Max amount', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: _clear, child: const Text('Clear'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton(
                      onPressed: _apply, child: const Text('Apply'))),
            ],
          ),
        ],
      ),
    );
  }
}