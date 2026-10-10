import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/local/tables.dart';

AppDatabase openTestDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

int _counter = 0;

Future<void> addTxn(
    AppDatabase db, {
      required double amount,
      required DateTime date,
      TransactionType type = TransactionType.expense,
      String category = 'Food',
      bool deleted = false,
    }) {
  _counter++;
  return db.into(db.transactions).insert(
    TransactionsCompanion.insert(
      id: 'test-$_counter',
      userId: 'u1',
      amount: amount,
      type: type,
      categoryId: category,
      accountId: 'acc1',
      transactionDate: date,
      createdAt: date.toUtc(),
      updatedAt: date.toUtc(),
      syncStatus: SyncStatus.synced,
      deletedAt: Value(deleted ? date.toUtc() : null),
    ),
  );
}