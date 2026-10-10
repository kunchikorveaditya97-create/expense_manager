import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../data/repositories/transaction_repository.dart';

class TransactionProvider extends ChangeNotifier {
  final ITransactionRepository _repository;
  final _uuid = const Uuid();

  VoidCallback? onTransactionDataChanged;

  List<Transaction> _transactions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;

  double _totalIncome = 0.0;
  double _totalExpense = 0.0;
  double _monthIncome = 0.0;
  double _monthExpense = 0.0;
  bool _hasAccounts = false;
  List<Account> _accounts = [];

  TransactionType? _filterType;
  String? _filterCategoryId;
  String? _filterAccountId;

  TransactionProvider(this._repository) {
    refreshAll();
  }

  List<Transaction> get transactions => _transactions;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  bool get hasAccounts => _hasAccounts;
  List<Account> get accounts => _accounts;

  String accountName(String idOrName) {
    for (final a in _accounts) {
      if (a.id == idOrName) return a.name;
    }
    return idOrName; // old transactions still hold the name
  }

  double get totalIncome => _hasAccounts ? _totalIncome : 0.0;
  double get totalExpense => _hasAccounts ? _totalExpense : 0.0;
  double get totalBalance => _hasAccounts ? (_totalIncome - _totalExpense) : 0.0;
  double get monthIncome => _hasAccounts ? _monthIncome : 0.0;
  double get monthExpense => _hasAccounts ? _monthExpense : 0.0;

  Future<void> refreshAll() async {
    _offset = 0;
    _hasMore = true;
    _transactions = [];
    await Future.wait([
      _fetchBatch(),
      refreshTotals(),
    ]);
    onTransactionDataChanged?.call();
  }

  Future<void> refreshTotals() async {
    final accountCount = await _repository.getAccountCount();
    _hasAccounts = accountCount > 0;
    _accounts = await _repository.getAllAccounts();
    _totalIncome = await _repository.getTotalIncome();
    _totalExpense = await _repository.getTotalExpense();
    final now = DateTime.now();
    _monthIncome = await _repository.getMonthTotal(
      TransactionType.income,
      now.month,
      now.year,
    );
    _monthExpense = await _repository.getMonthTotal(
      TransactionType.expense,
      now.month,
      now.year,
    );
    notifyListeners();
    onTransactionDataChanged?.call();
  }

  Future<void> fetchMore() async {
    if (_isLoading || !_hasMore) return;
    await _fetchBatch();
  }

  Future<void> _fetchBatch() async {
    _isLoading = true;
    notifyListeners();

    try {
      final fetched = await _repository.getPaginatedTransactions(
        limit: _limit,
        offset: _offset,
        type: _filterType,
        categoryId: _filterCategoryId,
        accountId: _filterAccountId,
      );

      if (fetched.length < _limit) {
        _hasMore = false;
      }

      _transactions.addAll(fetched);
      _offset += fetched.length;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createTransaction({
    required String userId,
    required double amount,
    required TransactionType type,
    required String categoryId,
    required String accountId,
    String? note,
    required DateTime transactionDate,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = TransactionsCompanion(
      id: Value(_uuid.v4()),
      userId: Value(userId),
      amount: Value(amount.abs()),
      type: Value(type),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      note: Value(note),
      transactionDate: Value(transactionDate),
      isRecurring: const Value(false),
      currency: const Value('INR'),
      createdAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(SyncStatus.pendingCreate),
    );

    await _repository.insertTransaction(companion);
    await refreshAll();
  }

  Future<void> updateTransaction({
    required String id,
    required double amount,
    required TransactionType type,
    required String categoryId,
    required String accountId,
    String? note,
    required DateTime transactionDate,
  }) async {
    final now = DateTime.now().toUtc();
    final companion = TransactionsCompanion(
      id: Value(id),
      amount: Value(amount.abs()),
      type: Value(type),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      note: Value(note),
      transactionDate: Value(transactionDate),
      updatedAt: Value(now),
      syncStatus: const Value(SyncStatus.pendingUpdate),
    );

    await _repository.updateTransaction(companion);
    await refreshAll();
  }

  Future<void> deleteTransaction(String id) async {
    await _repository.softDeleteTransaction(id);
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
    await refreshTotals();
  }

  Future<void> restoreTransaction(String id) async {
    await _repository.restoreTransaction(id);
    await refreshAll();
  }

  void setFilters({TransactionType? type, String? categoryId, String? accountId}) {
    _filterType = type;
    _filterCategoryId = categoryId;
    _filterAccountId = accountId;
    refreshAll();
  }

  void clearFilters() {
    _filterType = null;
    _filterCategoryId = null;
    _filterAccountId = null;
    refreshAll();
  }
}