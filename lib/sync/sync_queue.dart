import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class SyncQueue {
  SyncQueue(this._db);
  final AppDatabase _db;

  static const _waiting = [
    SyncStatus.pendingCreate,
    SyncStatus.pendingUpdate,
    SyncStatus.pendingDelete,
  ];
  static const _toPush = [
    SyncStatus.pendingCreate,
    SyncStatus.pendingUpdate,
    SyncStatus.pendingDelete,
    SyncStatus.failed,
  ];

  Expression<bool> _any(
      GeneratedColumnWithTypeConverter<SyncStatus, int> col,
      List<SyncStatus> statuses,
      ) =>
      statuses.map((s) => col.equalsValue(s)).reduce((a, b) => a | b);

  Future<List<Account>> pendingAccounts() =>
      (_db.select(_db.accounts)..where((t) => _any(t.syncStatus, _toPush))).get();

  Future<List<SavingsGoal>> pendingGoals() =>
      (_db.select(_db.savingsGoals)..where((t) => _any(t.syncStatus, _toPush)))
          .get();

  Future<List<Transaction>> pendingTransactions() =>
      (_db.select(_db.transactions)..where((t) => _any(t.syncStatus, _toPush)))
          .get();

  Future<int> pendingCount() async => await _count(_waiting);

  Future<int> failedCount() async => await _count(const [SyncStatus.failed]);

  Future<int> _count(List<SyncStatus> statuses) async {
    final a = await (_db.select(_db.accounts)
      ..where((t) => _any(t.syncStatus, statuses)))
        .get();
    final g = await (_db.select(_db.savingsGoals)
      ..where((t) => _any(t.syncStatus, statuses)))
        .get();
    final t = await (_db.select(_db.transactions)
      ..where((t) => _any(t.syncStatus, statuses)))
        .get();
    return a.length + g.length + t.length;
  }
}