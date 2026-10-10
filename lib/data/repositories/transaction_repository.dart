// lib/data/repositories/transaction_repository.dart
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import '../local/tables.dart';

abstract class ITransactionRepository {
  Future<int> insertTransaction(TransactionsCompanion companion);
  Future<bool> updateTransaction(TransactionsCompanion companion);
  Future<int> softDeleteTransaction(String id);
  Future<int> restoreTransaction(String id);
  Future<List<Transaction>> getPaginatedTransactions({
    required int limit,
    required int offset,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? searchQuery,
  });
  Future<double> getTotalIncome();
  Future<double> getTotalExpense();
  Future<double> getMonthTotal(TransactionType type, int month, int year);
  Future<int> getAccountCount();
}

class TransactionRepositoryImpl implements ITransactionRepository {
  final AppDatabase _db;

  TransactionRepositoryImpl(this._db);

  @override
  Future<int> insertTransaction(TransactionsCompanion companion) {
    return _db.into(_db.transactions).insert(companion);
  }

  @override
  Future<bool> updateTransaction(TransactionsCompanion companion) async {
    // Only update the fields that are present in companion, without requiring userId or createdAt
    final affectedRows = await (_db.update(_db.transactions)
      ..where((t) => t.id.equals(companion.id.value)))
        .write(companion);
    return affectedRows > 0;
  }

  @override
  Future<int> softDeleteTransaction(String id) {
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        syncStatus: const Value(SyncStatus.pendingDelete),
      ),
    );
  }

  @override
  Future<int> restoreTransaction(String id) {
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      const TransactionsCompanion(
        deletedAt: Value(null),
        syncStatus: Value(SyncStatus.pendingUpdate),
      ),
    );
  }

  @override
  Future<List<Transaction>> getPaginatedTransactions({
    required int limit,
    required int offset,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? searchQuery,
  }) {
    return _db.getPaginatedTransactions(
      limit: limit,
      offset: offset,
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      startDate: startDate,
      endDate: endDate,
      minAmount: minAmount,
      maxAmount: maxAmount,
      searchQuery: searchQuery,
    );
  }

  @override
  Future<double> getTotalIncome() => _db.getTotalIncome();

  @override
  Future<double> getTotalExpense() => _db.getTotalExpense();

  @override
  Future<double> getMonthTotal(TransactionType type, int month, int year) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return _db.getTotalBetween(type, start, end);
  }

  @override
  Future<int> getAccountCount() => _db.getAccountCount();
}