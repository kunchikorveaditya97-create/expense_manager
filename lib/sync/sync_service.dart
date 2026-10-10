// lib/sync/sync_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';
import 'conflict_resolver.dart';

class SyncService {
  final AppDatabase _db;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  SyncService(this._db);

  Future<int> getPendingChangesCount() async {
    final pending = await _db.getPendingTransactions();
    return pending.length;
  }

  CollectionReference<Map<String, dynamic>>? _getUserTxnCollection() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    return _firestore.collection('users').doc(user.uid).collection('transactions');
  }

  Future<void> syncLocalChangesToRemote() async {
    final collection = _getUserTxnCollection();
    if (collection == null) return;

    final pendingTxns = await _db.getPendingTransactions();

    for (final txn in pendingTxns) {
      final docRef = collection.doc(txn.id);

      if (txn.syncStatus == SyncStatus.pendingDelete) {
        await docRef.delete();
        await (_db.delete(_db.transactions)..where((t) => t.id.equals(txn.id))).go();
      } else {
        final payload = {
          'id': txn.id,
          'user_id': _auth.currentUser!.uid,
          'amount': txn.amount,
          'type': txn.type.name,
          'category_id': txn.categoryId,
          'account_id': txn.accountId,
          'note': txn.note,
          'transaction_date': txn.transactionDate.toIso8601String(),
          'updated_at': txn.updatedAt.toIso8601String(),
          'field_timestamps': txn.fieldTimestamps,
        };

        await docRef.set(payload, SetOptions(merge: true));

        await (_db.update(_db.transactions)..where((t) => t.id.equals(txn.id))).write(
          const TransactionsCompanion(
            syncStatus: Value(SyncStatus.synced),
          ),
        );
      }
    }
  }

  Future<void> pullRemoteChangesToLocal() async {
    final collection = _getUserTxnCollection();
    if (collection == null) return;

    final querySnapshot = await collection.get();

    for (final doc in querySnapshot.docs) {
      final remoteMap = doc.data();
      final id = remoteMap['id'] as String;

      final localList = await (_db.select(_db.transactions)..where((t) => t.id.equals(id))).get();

      if (localList.isEmpty) {
        await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            userId: _auth.currentUser!.uid,
            amount: (remoteMap['amount'] as num).toDouble(),
            type: TransactionType.values.byName(remoteMap['type'] as String),
            categoryId: remoteMap['category_id'] as String,
            accountId: remoteMap['account_id'] as String,
            note: Value(remoteMap['note'] as String?),
            transactionDate: DateTime.parse(remoteMap['transaction_date'] as String),
            createdAt: DateTime.parse(remoteMap['created_at'] ?? DateTime.now().toIso8601String()),
            updatedAt: DateTime.parse(remoteMap['updated_at'] as String),
            syncStatus: SyncStatus.synced,
          ),
        );
      } else {
        final local = localList.first;
        if (local.syncStatus != SyncStatus.synced) {
          final localMap = {
            'id': local.id,
            'amount': local.amount,
            'note': local.note,
            'category_id': local.categoryId,
            'account_id': local.accountId,
            'updated_at': local.updatedAt,
            'field_timestamps': local.fieldTimestamps,
          };

          final merged = ConflictResolver.resolveFieldLevelConflict(
            localRecord: localMap,
            remoteRecord: remoteMap,
          );

          await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
            TransactionsCompanion(
              amount: Value(merged['amount'] as double),
              note: Value(merged['note'] as String?),
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: Value(DateTime.parse(merged['updated_at'].toString())),
            ),
          );
        }
      }
    }
  }
}