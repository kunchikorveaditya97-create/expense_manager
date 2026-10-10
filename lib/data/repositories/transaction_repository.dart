import 'package:drift/drift.dart';
import '../../sync/conflict_resolver.dart';
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
  Future<List<Account>> getAllAccounts();
  Future<Map<String, double>> getAccountBalances();
  Future<void> insertRecurring(RecurringTransactionsCompanion companion);
}

class TransactionRepositoryImpl implements ITransactionRepository {
  final AppDatabase _db;

  TransactionRepositoryImpl(this._db);

  Future<Transaction?> _byId(String id) => (_db.select(_db.transactions)
    ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  @override
  Future<int> insertTransaction(TransactionsCompanion companion) {
    final created =
    companion.createdAt.present ? companion.createdAt.value : DateTime.now().toUtc();
    return _db.into(_db.transactions).insert(
      companion.copyWith(
        fieldTimestamps: Value(FieldTimestamps.forCreate(created)),
      ),
    );
  }

  @override
  Future<bool> updateTransaction(TransactionsCompanion companion) async {
    final id = companion.id.value;
    final old = await _byId(id);
    if (old == null) return false;

    final now =
    companion.updatedAt.present ? companion.updatedAt.value : DateTime.now().toUtc();

    final c = companion;
    final changed = <String>[
      if (c.amount.present && c.amount.value != old.amount) 'amount',
      if (c.type.present && c.type.value != old.type) 'type',
      if (c.categoryId.present && c.categoryId.value != old.categoryId)
        'category_id',
      if (c.accountId.present && c.accountId.value != old.accountId)
        'account_id',
      if (c.note.present && c.note.value != old.note) 'note',
      if (c.transactionDate.present &&
          !c.transactionDate.value.isAtSameMomentAs(old.transactionDate))
        'transaction_date',
    ];

    final stamps = FieldTimestamps.touch(
      old.fieldTimestamps,
      changed,
      now,
      baseline: old.updatedAt,
    );

    final affectedRows = await (_db.update(_db.transactions)
      ..where((t) => t.id.equals(id)))
        .write(companion.copyWith(
      updatedAt: Value(now),
      fieldTimestamps: Value(stamps),
    ));
    return affectedRows > 0;
  }

  @override
  Future<int> softDeleteTransaction(String id) async {
    final old = await _byId(id);
    if (old == null) return 0;
    final now = DateTime.now().toUtc();
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        fieldTimestamps: Value(FieldTimestamps.touch(
          old.fieldTimestamps,
          const ['deleted_at'],
          now,
          baseline: old.updatedAt,
        )),
        syncStatus: const Value(SyncStatus.pendingDelete),
      ),
    );
  }

  @override
  Future<int> restoreTransaction(String id) async {
    final old = await _byId(id);
    if (old == null) return 0;
    final now = DateTime.now().toUtc();
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        fieldTimestamps: Value(FieldTimestamps.touch(
          old.fieldTimestamps,
          const ['deleted_at'],
          now,
          baseline: old.updatedAt,
        )),
        syncStatus: const Value(SyncStatus.pendingUpdate),
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

  @override
  Future<List<Account>> getAllAccounts() => _db.getAllAccounts();

  @override
  Future<Map<String, double>> getAccountBalances() => _db.getAccountBalances();

  @override
  Future<void> insertRecurring(RecurringTransactionsCompanion companion) async {
    await _db.into(_db.recurringTransactions).insert(companion);
  }
}