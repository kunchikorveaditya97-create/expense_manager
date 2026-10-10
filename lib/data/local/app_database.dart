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

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Transactions,
  Accounts,
  Budgets,
  SavingsGoals,
  RecurringTransactions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedDefaultAccounts();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      for (final table in allTables) {
        await m.deleteTable(table.actualTableName);
      }
      await m.createAll();
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
      await _seedDefaultAccounts();
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
      query = query..where((t) => t.note.like('%${searchQuery.trim()}%'));
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

  Future<int> getAccountCount() async {
    final countExp = accounts.id.count();
    final query = selectOnly(accounts)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
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