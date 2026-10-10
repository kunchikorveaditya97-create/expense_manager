import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_service.dart';

enum SyncUiState { localOnly, synced, syncing, pending, offline, failed }

class SyncProvider extends ChangeNotifier with WidgetsBindingObserver {
  SyncProvider(
      this._service, {
        Connectivity? connectivity,
        Duration interval = const Duration(minutes: 5),
        Duration writeDebounce = const Duration(seconds: 5),
      })  : _connectivity = connectivity ?? Connectivity(),
        _interval = interval,
        _writeDebounce = writeDebounce;

  final SyncService _service;
  final Connectivity _connectivity;
  final Duration _interval;
  final Duration _writeDebounce;

  VoidCallback? onDataPulled;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<String?>? _authSub;
  Timer? _periodic;
  Timer? _debounce;
  Timer? _retry;

  bool _started = false;
  bool _disposed = false;
  bool _isSyncing = false;
  bool _rerun = false;
  bool _isOnline = true;
  bool _unreachable = false;
  bool _lastSyncFailed = false;
  int _waiting = 0;
  int _failed = 0;
  DateTime? _lastSyncAt;


  bool get isSyncing => _isSyncing;

  int get pendingCount => _waiting + _failed;
  int get failedCount => _failed;
  DateTime? get lastSyncAt => _lastSyncAt;
  bool get isOffline => !_isOnline || _unreachable;

  SyncUiState get state {
    if (!_service.isSignedIn) return SyncUiState.localOnly;
    if (_isSyncing) return SyncUiState.syncing;
    if (isOffline) return SyncUiState.offline;
    if (_lastSyncFailed || _failed > 0) return SyncUiState.failed;
    if (_waiting > 0) return SyncUiState.pending;
    return SyncUiState.synced;
  }

  String get label {
    String changes(int n) => n == 1 ? '1 change' : '$n changes';
    switch (state) {
      case SyncUiState.localOnly:
        return 'Local only';
      case SyncUiState.syncing:
        return 'Syncing...';
      case SyncUiState.offline:
        return pendingCount > 0
            ? 'Offline • ${changes(pendingCount)} will sync later'
            : 'Offline';
      case SyncUiState.failed:
        return 'Sync failed';
      case SyncUiState.pending:
        return '${changes(pendingCount)} waiting';
      case SyncUiState.synced:
        return 'Synced';
    }
  }


  Future<void> start() async {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);
    _isOnline = _hasNetwork(await _connectivity.checkConnectivity());
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    _authSub = _service.userChanges.skip(1).listen((_) {
      _unreachable = false;
      _lastSyncFailed = false;
      refreshStatus();
      syncAll();
    });
    _periodic = Timer.periodic(_interval, (_) => syncAll());

    await refreshStatus();
    unawaited(syncAll());
  }

  bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = _hasNetwork(results);
    final recovered = online && !_isOnline;
    _isOnline = online;
    if (recovered) _unreachable = false;
    _notify();
    if (recovered) syncAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncAll();
  }


  Future<void> refreshStatus() async {
    try {
      _waiting = await _service.getPendingChangesCount();
      _failed = await _service.getFailedCount();
      _lastSyncAt = await _service.lastSyncAt();
    } catch (e) {
      debugPrint('Sync status refresh failed: $e');
    }
    _notify();
  }

  Future<void> checkPendingChanges() => refreshStatus();

  Future<void> notifyLocalChange() async {
    await refreshStatus();
    if (pendingCount == 0) return;
    _debounce?.cancel();
    _debounce = Timer(_writeDebounce, syncAll);
  }

  Future<void> syncAll() async {
    if (_disposed) return;
    if (_isSyncing) {
      _rerun = true;
      return;
    }
    if (!_service.isSignedIn || !_isOnline) {
      await refreshStatus();
      return;
    }

    _isSyncing = true;
    _notify();
    try {
      final r = await _service.sync();
      _unreachable = r.offline;
      _lastSyncFailed = !r.offline && (r.error != null || r.failed > 0);
      if (r.pulled > 0) onDataPulled?.call();
      if (r.offline) _scheduleRetry();
    } catch (e) {
      debugPrint('Sync error: $e');
      _lastSyncFailed = true;
    } finally {
      _isSyncing = false;
      await refreshStatus();
    }

    if (_rerun) {
      _rerun = false;
      unawaited(syncAll());
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 30), syncAll);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _authSub?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}