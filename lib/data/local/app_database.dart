// lib/data/local/app_database.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:uuid/uuid.dart';
import 'tables.dart';
import 'db_key_service.dart';
import '../../core/categories.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Transactions,
  Accounts,
  Budgets,
  SavingsGoals,
  RecurringTransactions,
  Categories,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedDefaultAccounts();
      await _seedDefaultCategories();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        for (final table in allTables) {
          await m.deleteTable(table.actualTableName);
        }
        await m.createAll();
        await _seedDefaultCategories();
      } else if (from < 3) {
        await m.createTable(categories);
        await _seedDefaultCategories();
      }
    },
  );

  // --- Transactions Operations ---

  Future<void> _seedDefaultAccounts() async {
    const uuid = Uuid();
    final now = DateTime.now().toUtc();
    final defaultAccounts = ['Cash', 'Bank Account', 'Credit Card', 'UPI'];

    for (final name in defaultAccounts) {
      await into(accounts).insert(
        AccountsCompanion(
          id: Value(uuid.v4()),
          userId: const Value('default_user'),
          name: Value(name),
          type: Value(name.toLowerCase().replaceAll(' ', '_')),
          initialBalance: const Value(0.0),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
    }
  }

  Future<void> resetAllData() async {
    await transaction(() async {
      await delete(transactions).go();
      await delete(accounts).go();
      await delete(budgets).go();
      await delete(savingsGoals).go();
      await delete(recurringTransactions).go();
      await delete(categories).go();
      await _seedDefaultAccounts();
      await _seedDefaultCategories();
    });
  }

  Future<List<Transaction>> getRecentTransactions({int limit = 5}) {
    return (select(transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)])
      ..limit(limit))
        .get();
  }

  Future<int> insertTransaction(TransactionsCompanion entry) =>
      into(transactions).insert(entry);

  Future<bool> updateTransaction(TransactionsCompanion entry) =>
      update(transactions).replace(entry);

  Future<int> softDeleteTransaction(String id) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(DateTime.now().toUtc()),
        syncStatus: const Value(SyncStatus.pendingDelete),
      ),
    );
  }

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
    var query = select(transactions)..where((t) => t.deletedAt.isNull());

    if (type != null) {
      query = query..where((t) => t.type.equalsValue(type));
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query..where((t) => t.categoryId.equals(categoryId));
    }
    if (accountId != null && accountId.isNotEmpty) {
      query = query..where((t) => t.accountId.equals(accountId));
    }
    if (startDate != null) {
      query = query..where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }
    if (minAmount != null) {
      query = query..where((t) => t.amount.isBiggerOrEqualValue(minAmount));
    }
    if (maxAmount != null) {
      query = query..where((t) => t.amount.isSmallerOrEqualValue(maxAmount));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      query = query
        ..where((t) =>
        t.note.like(q) | t.categoryId.like(q) | t.amount.cast<String>().like(q));
    }

    query = query
      ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  Future<double> getTotalIncome() async {
    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(transactions.type.equalsValue(TransactionType.income))
      ..where(transactions.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(amountSum) ?? 0.0;
  }

  Future<double> getTotalExpense() async {
    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(transactions.type.equalsValue(TransactionType.expense))
      ..where(transactions.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(amountSum) ?? 0.0;
  }

  Future<double> getTotalBetween(
      TransactionType type,
      DateTime start,
      DateTime end,
      ) async {
    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(transactions.type.equalsValue(type))
      ..where(transactions.deletedAt.isNull())
      ..where(transactions.transactionDate.isBiggerOrEqualValue(start))
      ..where(transactions.transactionDate.isSmallerThanValue(end));
    final row = await query.getSingle();
    return row.read(amountSum) ?? 0.0;
  }

  Future<int> getAccountCount() async {
    final countExp = accounts.id.count();
    final query = selectOnly(accounts)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<List<Account>> getAllAccounts() {
    return (select(accounts)..where((a) => a.deletedAt.isNull())).get();
  }

  Future<void> _seedDefaultCategories() async {
    const uuid = Uuid();
    final now = DateTime.now().toUtc();
    for (final (name, icon) in defaultExpenseCategories) {
      await into(categories).insert(CategoriesCompanion.insert(
        id: uuid.v4(),
        userId: 'default_user',
        name: name,
        type: TransactionType.expense,
        iconName: icon,
        createdAt: now,
      ));
    }
    for (final (name, icon) in defaultIncomeCategories) {
      await into(categories).insert(CategoriesCompanion.insert(
        id: uuid.v4(),
        userId: 'default_user',
        name: name,
        type: TransactionType.income,
        iconName: icon,
        createdAt: now,
      ));
    }
  }

  Future<List<Category>> getAllCategories() => select(categories).get();

  Future<void> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  Future<bool> categoryNameExists(String name, TransactionType type) async {
    final rows = await (select(categories)
      ..where((c) => c.name.lower().equals(name.toLowerCase()) &
      c.type.equalsValue(type))
      ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<void> updateCategoryStyle(String id, String iconName, int? colorValue) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        iconName: Value(iconName),
        colorValue: Value(colorValue),
      ),
    );
  }

  Future<void> setCategoryArchived(String id, bool archived) {
    return (update(categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(isArchived: Value(archived)));
  }

  Future<void> insertAccount(String name, String type, double initialBalance) {
    final now = DateTime.now().toUtc();
    return into(accounts).insert(AccountsCompanion(
      id: Value(const Uuid().v4()),
      userId: const Value('default_user'),
      name: Value(name),
      type: Value(type),
      initialBalance: Value(initialBalance),
      createdAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(SyncStatus.synced),
    ));
  }

  Future<void> updateAccountDetails(String id, String name, double initialBalance) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        initialBalance: Value(initialBalance),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Returns false (and does nothing) if any transaction uses this account.
  Future<bool> deleteAccountIfUnused(String id) async {
    final usedByTxn = await (select(transactions)
      ..where((t) => t.accountId.equals(id))
      ..limit(1))
        .get();
    final usedByRecurring = await (select(recurringTransactions)
      ..where((t) => t.accountId.equals(id))
      ..limit(1))
        .get();
    if (usedByTxn.isNotEmpty || usedByRecurring.isNotEmpty) return false;

    await (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(deletedAt: Value(DateTime.now().toUtc())),
    );
    return true;
  }

  Future<List<Transaction>> getTransactionsBetween(DateTime start, DateTime end) {
    return (select(transactions)
      ..where((t) =>
      t.deletedAt.isNull() &
      t.transactionDate.isBiggerOrEqualValue(start) &
      t.transactionDate.isSmallerThanValue(end)))
        .get();
  }

  Future<double?> getBudgetLimit(String categoryId, int month, int year) async {
    final row = await (select(budgets)
      ..where((b) =>
      b.categoryId.equals(categoryId) &
      b.month.equals(month) &
      b.year.equals(year))
      ..limit(1))
        .getSingleOrNull();
    return row?.limitAmount;
  }

  /// amount <= 0 removes the budget.
  Future<void> setBudgetLimit(
      String categoryId, int month, int year, double amount) async {
    final existing = await (select(budgets)
      ..where((b) =>
      b.categoryId.equals(categoryId) &
      b.month.equals(month) &
      b.year.equals(year))
      ..limit(1))
        .getSingleOrNull();

    if (amount <= 0) {
      if (existing != null) {
        await (delete(budgets)..where((b) => b.id.equals(existing.id))).go();
      }
      return;
    }
    if (existing == null) {
      await into(budgets).insert(BudgetsCompanion.insert(
        id: const Uuid().v4(),
        categoryId: categoryId,
        limitAmount: amount,
        month: month,
        year: year,
        syncStatus: SyncStatus.synced,
      ));
    } else {
      await (update(budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(limitAmount: Value(amount)));
    }
  }

  Future<Map<String, double>> getCategoryBudgets(int month, int year) async {
    final rows = await (select(budgets)
      ..where((b) =>
      b.month.equals(month) &
      b.year.equals(year) &
      b.categoryId.equals('ALL').not()))
        .get();
    return {for (final r in rows) r.categoryId: r.limitAmount};
  }

  Future<Map<String, double>> getExpenseByCategory(
      DateTime start, DateTime end) async {
    final sum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([transactions.categoryId, sum])
      ..where(transactions.type.equalsValue(TransactionType.expense) &
      transactions.deletedAt.isNull() &
      transactions.transactionDate.isBiggerOrEqualValue(start) &
      transactions.transactionDate.isSmallerThanValue(end))
      ..groupBy([transactions.categoryId]);
    final rows = await query.get();
    return {
      for (final r in rows) r.read(transactions.categoryId)!: r.read(sum) ?? 0.0,
    };
  }

  Future<Map<String, double>> _sumByAccount(TransactionType type) async {
    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([transactions.accountId, amountSum])
      ..where(transactions.type.equalsValue(type))
      ..where(transactions.deletedAt.isNull())
      ..groupBy([transactions.accountId]);
    final rows = await query.get();
    return {
      for (final r in rows)
        r.read(transactions.accountId)!: r.read(amountSum) ?? 0.0,
    };
  }

  Future<Map<String, double>> getAccountBalances() async {
    final income = await _sumByAccount(TransactionType.income);
    final expense = await _sumByAccount(TransactionType.expense);
    final accs = await getAllAccounts();
    return {
      for (final a in accs)
        a.id: a.initialBalance + (income[a.id] ?? 0.0) - (expense[a.id] ?? 0.0),
    };
  }

  Future<List<Transaction>> getPendingTransactions() {
    return (select(transactions)
      ..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not()))
        .get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'secure_expense_manager.db'));

    final key = await DbKeyService.getOrCreateKey();
    const legacyKey = DbKeyService.legacyKey;

    return NativeDatabase.createInBackground(
      file,
      isolateSetup: () async {
        await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
        open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      },
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
        try {
          // Fails if the database still uses the old hardcoded key
          rawDb.select('SELECT count(*) FROM sqlite_master;');
        } catch (_) {
          rawDb.execute("PRAGMA key = '$legacyKey';");
          rawDb.select('SELECT count(*) FROM sqlite_master;');
          rawDb.execute("PRAGMA rekey = '$key';");
        }
      },
    );
  });
}