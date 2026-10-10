// lib/sync/sync_service.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/app_database.dart';
import '../data/local/tables.dart';
import 'conflict_resolver.dart';
import 'sync_queue.dart';
import 'sync_remote.dart';

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.failed = 0,
    this.offline = false,
    this.localOnly = false,
    this.error,
  });

  final int pushed;
  final int pulled;
  final int failed;
  final bool offline;
  final bool localOnly;
  final Object? error;

  bool get ok => !offline && !localOnly && error == null && failed == 0;
}

class _Counts {
  int pushed = 0;
  int pulled = 0;
  int failed = 0;
}

/// Local <-> cloud synchronisation.
///
/// Order matters: **pull first, then push.** Pulling first merges remote edits
/// into pending local rows (field by field), so the push uploads the merged
/// result instead of blindly overwriting another device's changes.
/// Accounts go first so transactions never reference a missing account.
class SyncService {
  SyncService(this._db, this._remote) : queue = SyncQueue(_db);

  final AppDatabase _db;
  final SyncRemote _remote;
  final SyncQueue queue;
  bool _running = false;

  bool get isSignedIn => _remote.userId != null;
  Stream<String?> get userChanges => _remote.userIdChanges;

  Future<int> getPendingChangesCount() => queue.pendingCount();
  Future<int> getFailedCount() => queue.failedCount();

  // ---------------------------------------------------------------- run ---

  Future<SyncResult> sync() async {
    final uid = _remote.userId;
    if (uid == null) return const SyncResult(localOnly: true);
    if (_running) return const SyncResult();
    _running = true;
    final c = _Counts();
    try {
      await _pull(uid, 'accounts', c, (m) => _applyAccount(uid, m));
      await _pull(uid, 'goals', c, (m) => _applyGoal(uid, m));
      await _pull(uid, 'transactions', c, (m) => _applyTransaction(uid, m));

      await _pushAccounts(uid, c);
      await _pushGoals(uid, c);
      await _pushTransactions(uid, c);

      if (c.failed == 0) {
        final p = await SharedPreferences.getInstance();
        await p.setInt(
            _lastSyncKey(uid), DateTime.now().toUtc().millisecondsSinceEpoch);
        await _purgeTombstones();
      }
      return SyncResult(pushed: c.pushed, pulled: c.pulled, failed: c.failed);
    } on SyncOfflineException {
      return SyncResult(pushed: c.pushed, pulled: c.pulled, offline: true);
    } catch (e, st) {
      debugPrint('Sync error: $e\n$st');
      return SyncResult(
          pushed: c.pushed, pulled: c.pulled, failed: c.failed, error: e);
    } finally {
      _running = false;
    }
  }

  // --------------------------------------------------------------- pull ---

  Future<void> _pull(
      String uid,
      String collection,
      _Counts c,
      Future<bool> Function(Map<String, dynamic>) apply,
      ) async {
    final since = await _cursor(uid, collection);
    final batch = await _remote.fetchChangedSince(collection, since);

    var clean = true;
    for (final doc in batch.docs) {
      try {
        if (await apply(doc)) c.pulled++;
      } catch (e) {
        clean = false;
        c.failed++;
        debugPrint('Sync: could not apply $collection/${doc['id']}: $e');
      }
    }
    // Only advance the cursor when everything applied, so failures are retried.
    if (clean && batch.maxSyncedAt != null) {
      await _saveCursor(uid, collection, batch.maxSyncedAt!);
    }
  }

  /// Shared apply logic. Returns true when the local row changed.
  Future<bool> _applyRemote<T>({
    required Map<String, dynamic> remote,
    required Future<T?> Function(String id) findLocal,
    required DateTime Function(T) updatedAtOf,
    required SyncStatus Function(T) statusOf,
    required Map<String, dynamic> Function(T) toMap,
    required List<String> fields,
    required Future<void> Function(Map<String, dynamic> data, SyncStatus status)
    write,
  }) async {
    final id = remote['id'] as String;
    final local = await findLocal(id);

    // New to this device (includes tombstones, so deletes propagate).
    if (local == null) {
      await write(remote, SyncStatus.synced);
      return true;
    }

    // Local copy is clean: take the remote version only if it is newer.
    if (statusOf(local) == SyncStatus.synced) {
      final rUpdated = ConflictResolver.parseTime(remote['updated_at']);
      if (rUpdated == null || !rUpdated.isAfter(updatedAtOf(local).toUtc())) {
        return false;
      }
      await write(remote, SyncStatus.synced);
      return true;
    }

    // Both sides changed: field-level merge. If local contributed anything the
    // row stays pending so the merged result is uploaded.
    final r = ConflictResolver.merge(
        local: toMap(local), remote: remote, fields: fields);
    await write(r.record,
        r.needsPush ? SyncStatus.pendingUpdate : SyncStatus.synced);
    return true;
  }

  Future<bool> _applyTransaction(String uid, Map<String, dynamic> m) =>
      _applyRemote<Transaction>(
        remote: m,
        findLocal: (id) => (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id)))
            .getSingleOrNull(),
        updatedAtOf: (t) => t.updatedAt,
        statusOf: (t) => t.syncStatus,
        toMap: (t) => _txnToMap(t, uid),
        fields: ConflictResolver.transactionFields,
        write: (data, status) => _writeTransaction(uid, data, status),
      );

  Future<bool> _applyAccount(String uid, Map<String, dynamic> m) =>
      _applyRemote<Account>(
        remote: m,
        findLocal: (id) => (_db.select(_db.accounts)
          ..where((t) => t.id.equals(id)))
            .getSingleOrNull(),
        updatedAtOf: (a) => a.updatedAt,
        statusOf: (a) => a.syncStatus,
        toMap: (a) => _accountToMap(a, uid),
        fields: ConflictResolver.accountFields,
        write: (data, status) => _writeAccount(uid, data, status),
      );

  Future<bool> _applyGoal(String uid, Map<String, dynamic> m) =>
      _applyRemote<SavingsGoal>(
        remote: m,
        findLocal: (id) => (_db.select(_db.savingsGoals)
          ..where((t) => t.id.equals(id)))
            .getSingleOrNull(),
        updatedAtOf: (g) => g.updatedAt,
        statusOf: (g) => g.syncStatus,
        toMap: (g) => _goalToMap(g, uid),
        fields: ConflictResolver.goalFields,
        write: (data, status) => _writeGoal(uid, data, status),
      );

  // --------------------------------------------------------------- push ---

  Future<void> _push<T>({
    required String collection,
    required List<T> rows,
    required String Function(T) idOf,
    required Map<String, dynamic> Function(T) toMap,
    required Future<void> Function(T) markSynced,
    required Future<void> Function(T) markFailed,
    required _Counts counts,
  }) async {
    for (final row in rows) {
      try {
        await _remote.upsert(collection, idOf(row), toMap(row));
        await markSynced(row);
        counts.pushed++;
      } on SyncOfflineException {
        rethrow; // stop the run; every remaining row stays pending
      } catch (e) {
        // One bad record must not block the others.
        debugPrint('Sync: push failed for $collection/${idOf(row)}: $e');
        await markFailed(row);
        counts.failed++;
      }
    }
  }

  // markSynced only matches if updatedAt is unchanged, so an edit made while
  // the upload was in flight stays pending instead of being marked synced.

  Future<void> _pushTransactions(String uid, _Counts c) async => _push<Transaction>(
    collection: 'transactions',
    rows: await queue.pendingTransactions(),
    idOf: (r) => r.id,
    toMap: (r) => _txnToMap(r, uid),
    markSynced: (r) => (_db.update(_db.transactions)
      ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
        .write(const TransactionsCompanion(
        syncStatus: Value(SyncStatus.synced))),
    markFailed: (r) => (_db.update(_db.transactions)
      ..where((t) => t.id.equals(r.id)))
        .write(const TransactionsCompanion(
        syncStatus: Value(SyncStatus.failed))),
    counts: c,
  );

  Future<void> _pushAccounts(String uid, _Counts c) async => _push<Account>(
    collection: 'accounts',
    rows: await queue.pendingAccounts(),
    idOf: (r) => r.id,
    toMap: (r) => _accountToMap(r, uid),
    markSynced: (r) => (_db.update(_db.accounts)
      ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
        .write(const AccountsCompanion(syncStatus: Value(SyncStatus.synced))),
    markFailed: (r) => (_db.update(_db.accounts)
      ..where((t) => t.id.equals(r.id)))
        .write(const AccountsCompanion(syncStatus: Value(SyncStatus.failed))),
    counts: c,
  );

  Future<void> _pushGoals(String uid, _Counts c) async => _push<SavingsGoal>(
    collection: 'goals',
    rows: await queue.pendingGoals(),
    idOf: (r) => r.id,
    toMap: (r) => _goalToMap(r, uid),
    markSynced: (r) => (_db.update(_db.savingsGoals)
      ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
        .write(const SavingsGoalsCompanion(
        syncStatus: Value(SyncStatus.synced))),
    markFailed: (r) => (_db.update(_db.savingsGoals)
      ..where((t) => t.id.equals(r.id)))
        .write(const SavingsGoalsCompanion(
        syncStatus: Value(SyncStatus.failed))),
    counts: c,
  );

  // ----------------------------------------------------------- mappers ---

  String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

  Map<String, dynamic> _txnToMap(Transaction t, String uid) => {
    'id': t.id,
    'user_id': uid,
    'amount': t.amount,
    'type': t.type.name,
    'category_id': t.categoryId,
    'account_id': t.accountId,
    'note': t.note,
    'transaction_date': _iso(t.transactionDate),
    'is_recurring': t.isRecurring,
    'currency': t.currency,
    'field_timestamps': _decodeStamps(t.fieldTimestamps),
    'created_at': _iso(t.createdAt),
    'updated_at': _iso(t.updatedAt),
    'deleted_at': _iso(t.deletedAt),
  };

  Map<String, dynamic> _accountToMap(Account a, String uid) => {
    'id': a.id,
    'user_id': uid,
    'name': a.name,
    'type': a.type,
    'initial_balance': a.initialBalance,
    'created_at': _iso(a.createdAt),
    'updated_at': _iso(a.updatedAt),
    'deleted_at': _iso(a.deletedAt),
  };

  Map<String, dynamic> _goalToMap(SavingsGoal g, String uid) => {
    'id': g.id,
    'user_id': uid,
    'name': g.name,
    'target_amount': g.targetAmount,
    'current_amount': g.currentAmount,
    'target_date': _iso(g.targetDate),
    'icon_name': g.iconName,
    'created_at': _iso(g.createdAt),
    'updated_at': _iso(g.updatedAt),
    'deleted_at': _iso(g.deletedAt),
  };

  Map<String, dynamic> _decodeStamps(String? json) {
    if (json == null || json.isEmpty) return <String, dynamic>{};
    try {
      final d = jsonDecode(json);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return <String, dynamic>{};
  }

  String? _encodeStamps(dynamic v) {
    if (v is Map) return jsonEncode(v);
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  DateTime _time(dynamic v, {DateTime? or}) =>
      ConflictResolver.parseTime(v) ?? or ?? DateTime.now().toUtc();

  // Upserts so the same code path handles insert and update.

  Future<void> _writeTransaction(
      String uid, Map<String, dynamic> m, SyncStatus status) =>
      _db.into(_db.transactions).insertOnConflictUpdate(TransactionsCompanion(
        id: Value(m['id'] as String),
        userId: Value(uid),
        amount: Value((m['amount'] as num).toDouble()),
        type: Value(TransactionType.values.byName(m['type'] as String)),
        categoryId: Value(m['category_id'] as String),
        accountId: Value(m['account_id'] as String),
        note: Value(m['note'] as String?),
        transactionDate: Value(_time(m['transaction_date'])),
        isRecurring: Value(m['is_recurring'] as bool? ?? false),
        currency: Value(m['currency'] as String? ?? 'INR'),
        fieldTimestamps: Value(_encodeStamps(m['field_timestamps'])),
        createdAt: Value(_time(m['created_at'], or: _time(m['updated_at']))),
        updatedAt: Value(_time(m['updated_at'])),
        deletedAt: Value(ConflictResolver.parseTime(m['deleted_at'])),
        syncStatus: Value(status),
      ));

  Future<void> _writeAccount(
      String uid, Map<String, dynamic> m, SyncStatus status) =>
      _db.into(_db.accounts).insertOnConflictUpdate(AccountsCompanion(
        id: Value(m['id'] as String),
        userId: Value(uid),
        name: Value(m['name'] as String),
        type: Value(m['type'] as String),
        initialBalance: Value((m['initial_balance'] as num? ?? 0).toDouble()),
        createdAt: Value(_time(m['created_at'], or: _time(m['updated_at']))),
        updatedAt: Value(_time(m['updated_at'])),
        deletedAt: Value(ConflictResolver.parseTime(m['deleted_at'])),
        syncStatus: Value(status),
      ));

  Future<void> _writeGoal(
      String uid, Map<String, dynamic> m, SyncStatus status) =>
      _db.into(_db.savingsGoals).insertOnConflictUpdate(SavingsGoalsCompanion(
        id: Value(m['id'] as String),
        userId: Value(uid),
        name: Value(m['name'] as String),
        targetAmount: Value((m['target_amount'] as num).toDouble()),
        currentAmount: Value((m['current_amount'] as num? ?? 0).toDouble()),
        targetDate: Value(_time(m['target_date'])),
        iconName: Value(m['icon_name'] as String? ?? 'savings'),
        createdAt: Value(_time(m['created_at'], or: _time(m['updated_at']))),
        updatedAt: Value(_time(m['updated_at'])),
        deletedAt: Value(ConflictResolver.parseTime(m['deleted_at'])),
        syncStatus: Value(status),
      ));

  // --------------------------------------------------- housekeeping/state ---

  /// Soft-deleted transactions that are fully synced and older than 30 days
  /// are removed locally. The cloud keeps its tombstone for other devices.
  Future<void> _purgeTombstones() async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
    await (_db.delete(_db.transactions)
      ..where((t) =>
      t.deletedAt.isSmallerThanValue(cutoff) &
      t.syncStatus.equalsValue(SyncStatus.synced)))
        .go();
  }

  String _cursorKey(String uid, String c) => 'sync_cursor_${uid}_$c';
  String _lastSyncKey(String uid) => 'sync_last_$uid';

  Future<DateTime?> _cursor(String uid, String collection) async {
    final p = await SharedPreferences.getInstance();
    final micros = p.getInt(_cursorKey(uid, collection));
    return micros == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  }

  Future<void> _saveCursor(String uid, String collection, DateTime at) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_cursorKey(uid, collection), at.microsecondsSinceEpoch);
  }

  /// Time of the last fully successful sync for the current user.
  Future<DateTime?> lastSyncAt() async {
    final uid = _remote.userId;
    if (uid == null) return null;
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_lastSyncKey(uid));
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  /// Call after "Reset local data" so the next sync re-downloads everything.
  Future<void> resetSyncState() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith('sync_')).toList()) {
      await p.remove(k);
    }
  }
}