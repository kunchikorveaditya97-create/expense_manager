// lib/features/transactions/add_edit_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/currency_provider.dart';

class AddEditTransactionScreen extends StatefulWidget {
  final Transaction? transaction;

  const AddEditTransactionScreen({super.key, this.transaction});

  @override
  State<AddEditTransactionScreen> createState() => _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _noteController;

  late TransactionType _selectedType;
  late String _selectedCategory;
  late String _selectedAccount;
  late DateTime _selectedDate;
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Food',
    'Shopping',
    'Bills',
    'Transport',
    'Salary',
    'Investment',
    'Other'
  ];
  final List<String> _accounts = ['Cash', 'Bank Account', 'Credit Card', 'UPI'];

  @override
  void initState() {
    super.initState();
    final txn = widget.transaction;
    _selectedType = txn?.type ?? TransactionType.expense;
    _selectedCategory = txn?.categoryId ?? _categories.first;
    _selectedAccount = txn?.accountId ?? _accounts.first;
    _selectedDate = txn?.transactionDate ?? DateTime.now();

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

      if (isEditing) {
        await provider.updateTransaction(
          id: widget.transaction!.id,
          amount: enteredAmount,
          type: _selectedType,
          categoryId: _selectedCategory,
          accountId: _selectedAccount,
          note: trimmedNote,
          transactionDate: _selectedDate,
        );
      } else {
        await provider.createTransaction(
          userId: 'default_user',
          amount: enteredAmount,
          type: _selectedType,
          categoryId: _selectedCategory,
          accountId: _selectedAccount,
          note: trimmedNote,
          transactionDate: _selectedDate,
        );
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
                setState(() => _selectedType = set.first);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${context.watch<CurrencyProvider>().current.symbol} ',
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
            DropdownButtonFormField<String>(
              value: _categories.contains(_selectedCategory)
                  ? _selectedCategory
                  : _categories.first,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _accounts.contains(_selectedAccount)
                  ? _selectedAccount
                  : _accounts.first,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
              ),
              items: _accounts.map((acc) {
                return DropdownMenuItem(value: acc, child: Text(acc));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedAccount = val);
              },
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitForm,
              icon: _isSubmitting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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