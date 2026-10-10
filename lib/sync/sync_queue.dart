// lib/sync/sync_queue.dart
//
// The outbox: every local row that still has to reach the cloud.
// A row is queued by its syncStatus (pendingCreate / pendingUpdate /
// pendingDelete / failed). There is no separate table, so the queue can never
// disagree with the data.
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

  // Rows to push (failed ones are retried on every run).
  Future<List<Account>> pendingAccounts() =>
      (_db.select(_db.accounts)..where((t) => _any(t.syncStatus, _toPush))).get();

  Future<List<SavingsGoal>> pendingGoals() =>
      (_db.select(_db.savingsGoals)..where((t) => _any(t.syncStatus, _toPush)))
          .get();

  Future<List<Transaction>> pendingTransactions() =>
      (_db.select(_db.transactions)..where((t) => _any(t.syncStatus, _toPush)))
          .get();

  /// Changes waiting to upload (excludes failed ones).
  Future<int> pendingCount() async => await _count(_waiting);

  /// Changes whose last upload attempt was rejected by the server.
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