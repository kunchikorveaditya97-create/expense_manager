// lib/features/transactions/add_edit_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/category_provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/currency_provider.dart';
import '../../services/recurring_processor.dart';

class AddEditTransactionScreen extends StatefulWidget {
  final Transaction? transaction;

  const AddEditTransactionScreen({super.key, this.transaction});

  @override
  State<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _noteController;

  late TransactionType _selectedType;
  late String _selectedCategory;
  String? _selectedAccount;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isRecurring = false;
  String _frequency = 'monthly';
  bool _isSubmitting = false;

  List<String> get _categories =>
      context.read<CategoryProvider>().activeNames(_selectedType);

  @override
  void initState() {
    super.initState();
    final txn = widget.transaction;
    _selectedType = txn?.type ?? TransactionType.expense;
    _selectedCategory = txn?.categoryId ?? _categories.first;
    _selectedAccount = txn?.accountId;
    _selectedDate = txn?.transactionDate ?? DateTime.now();
    _selectedTime = TimeOfDay.fromDateTime(_selectedDate);

    _amountController = TextEditingController(
      text: txn != null ? txn.amount.toStringAsFixed(2) : '',
    );
    _noteController = TextEditingController(text: txn?.note ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _resolveAccountId(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    for (final a in accounts) {
      if (a.id == _selectedAccount || a.name == _selectedAccount) return a.id;
    }
    return accounts.first.id;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked =
    await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  DateTime get _combinedDateTime => DateTime(
    _selectedDate.year,
    _selectedDate.month,
    _selectedDate.day,
    _selectedTime.hour,
    _selectedTime.minute,
  );

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final enteredAmount = double.parse(_amountController.text.trim());
      final trimmedNote = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();

      final isEditing = widget.transaction != null;
      final provider = context.read<TransactionProvider>();

      final accountId = _resolveAccountId(provider.accounts);
      if (accountId == null) {
        throw Exception('No account available');
      }
      final when = _combinedDateTime;

      if (isEditing) {
        await provider.updateTransaction(
          id: widget.transaction!.id,
          amount: enteredAmount,
          type: _selectedType,
          categoryId: _selectedCategory,
          accountId: accountId,
          note: trimmedNote,
          transactionDate: when,
        );
      } else {
        await provider.createTransaction(
          userId: 'default_user',
          amount: enteredAmount,
          type: _selectedType,
          categoryId: _selectedCategory,
          accountId: accountId,
          note: trimmedNote,
          transactionDate: when,
        );

        if (_isRecurring) {
          await provider.createRecurring(
            userId: 'default_user',
            amount: enteredAmount,
            type: _selectedType,
            categoryId: _selectedCategory,
            accountId: accountId,
            note: trimmedNote,
            frequency: _frequency,
            firstDate: nextRecurrence(when, _frequency),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, stack) {
      debugPrint('DATABASE ERROR WHILE SAVING: $e');
      debugPrint(stack.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save transaction: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.transaction != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Transaction' : 'Add Transaction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward, color: Colors.red),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward, color: Colors.green),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (set) {
                setState(() {
                  _selectedType = set.first;
                  if (!_categories.contains(_selectedCategory)) {
                    _selectedCategory = _categories.first;
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText:
                '${context.watch<CurrencyProvider>().current.symbol} ',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an amount';
                }
                final numVal = double.tryParse(value.trim());
                if (numVal == null || numVal <= 0) {
                  return 'Please enter a valid amount greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Builder(builder: (context) {
              context.watch<CategoryProvider>();
              final cats = _categories.contains(_selectedCategory)
                  ? _categories
                  : [..._categories, _selectedCategory];
              return DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: cats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              );
            }),
            const SizedBox(height: 20),
            Builder(builder: (context) {
              final accounts = context.watch<TransactionProvider>().accounts;
              return DropdownButtonFormField<String>(
                value: _resolveAccountId(accounts),
                decoration: const InputDecoration(
                  labelText: 'Account',
                  border: OutlineInputBorder(),
                ),
                items: accounts.map((a) {
                  return DropdownMenuItem(value: a.id, child: Text(a.name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedAccount = val);
                },
              );
            }),
            const SizedBox(height: 20),
            ListTile(
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              leading: const Icon(Icons.calendar_today),
              title: const Text('Transaction Date'),
              subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickDate,
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              leading: const Icon(Icons.access_time),
              title: const Text('Time'),
              subtitle: Text(_selectedTime.format(context)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickTime,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (!isEditing) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recurring transaction'),
                subtitle: const Text('Repeats automatically'),
                value: _isRecurring,
                onChanged: (v) => setState(() => _isRecurring = v),
              ),
              if (_isRecurring)
                DropdownButtonFormField<String>(
                  value: _frequency,
                  decoration: const InputDecoration(
                    labelText: 'Repeats',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _frequency = v);
                  },
                ),
            ],
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitForm,
              icon: _isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.check),
              label: Text(
                _isSubmitting
                    ? 'Saving...'
                    : (isEditing ? 'Update Transaction' : 'Save Transaction'),
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}