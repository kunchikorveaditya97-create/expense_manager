// lib/sync/sync_provider.dart
import 'package:flutter/foundation.dart';
import 'sync_service.dart';

class SyncProvider extends ChangeNotifier {
  final SyncService _syncService;
  bool _isSyncing = false;
  int _pendingCount = 0;

  SyncProvider(this._syncService) {
    checkPendingChanges();
  }

  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;

  Future<void> checkPendingChanges() async {
    _pendingCount = await _syncService.getPendingChangesCount();
    notifyListeners();
  }

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      await _syncService.syncLocalChangesToRemote();
      await _syncService.pullRemoteChangesToLocal();
      await checkPendingChanges();
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}