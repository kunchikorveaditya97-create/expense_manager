import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SyncOfflineException implements Exception {
  SyncOfflineException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'SyncOfflineException($cause)';
}

class RemoteBatch {
  const RemoteBatch(this.docs, this.maxSyncedAt);
  final List<Map<String, dynamic>> docs;

  final DateTime? maxSyncedAt;
}

abstract class SyncRemote {
  String? get userId;
  Stream<String?> get userIdChanges;

  Future<void> upsert(String collection, String id, Map<String, dynamic> data);

  Future<RemoteBatch> fetchChangedSince(String collection, DateTime? since);
}

class FirestoreSyncRemote implements SyncRemote {
  FirestoreSyncRemote({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.timeout = const Duration(seconds: 12),
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final Duration timeout;

  FirebaseFirestore get _fs => _firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _fa => _auth ?? FirebaseAuth.instance;

  static const _offlineCodes = {
    'unavailable',
    'deadline-exceeded',
    'network-request-failed',
    'cancelled',
  };

  @override
  String? get userId {
    try {
      final u = _fa.currentUser;
      return (u == null || u.isAnonymous) ? null : u.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String?> get userIdChanges {
    try {
      return _fa.authStateChanges().map((_) => userId).distinct();
    } catch (_) {
      return const Stream.empty();
    }
  }

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _fs.collection('users').doc(uid).collection(name);

  String _requireUid() {
    final uid = userId;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  @override
  Future<void> upsert(
      String collection, String id, Map<String, dynamic> data) async {
    final uid = _requireUid();
    await _guard(() => _col(uid, collection).doc(id).set(
      {...data, 'synced_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    ));
  }

  @override
  Future<RemoteBatch> fetchChangedSince(
      String collection, DateTime? since) async {
    final uid = _requireUid();
    final base = _col(uid, collection);

    final Query<Map<String, dynamic>> query = since == null
        ? base
        : base
        .where('synced_at', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('synced_at');

    final snap =
    await _guard(() => query.get(const GetOptions(source: Source.server)));

    DateTime? maxAt;
    final docs = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final data = Map<String, dynamic>.from(d.data());
      final ts = data.remove('synced_at');
      if (ts is Timestamp) {
        final at = ts.toDate().toUtc();
        if (maxAt == null || at.isAfter(maxAt)) maxAt = at;
      }
      data['id'] ??= d.id;
      docs.add(data);
    }
    return RemoteBatch(docs, maxAt);
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(timeout);
    } on TimeoutException catch (e) {
      throw SyncOfflineException(e);
    } on FirebaseException catch (e) {
      if (_offlineCodes.contains(e.code)) throw SyncOfflineException(e);
      rethrow;
    }
  }
}