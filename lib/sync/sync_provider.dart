// lib/sync/sync_provider.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_service.dart';

enum SyncUiState { localOnly, synced, syncing, pending, offline, failed }

/// Drives automatic sync and exposes status for the UI.
///
/// Sync is triggered by: app start, sign-in/out, connectivity coming back,
/// app resume, a debounced run after local writes, a periodic timer, and a
/// short retry after the server could not be reached. None of it blocks the
/// UI: every screen reads the local DB.
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
  // Longer than the 3 s "Undo" window on delete, so an undone delete is
  // normally never uploaded at all.
  final Duration _writeDebounce;

  /// Called after a sync brought remote changes into the local DB, so the
  /// app can reload providers.
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
  bool _isOnline = true; // interface-level, refined by sync results
  bool _unreachable = false; // interface up but cloud not reachable
  bool _lastSyncFailed = false;
  int _waiting = 0;
  int _failed = 0;
  DateTime? _lastSyncAt;

  // ------------------------------------------------------------ getters ---

  bool get isSyncing => _isSyncing;

  /// Everything not yet in the cloud (waiting + failed).
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

  // ---------------------------------------------------------- lifecycle ---

  /// Call once, after callbacks are wired (see main.dart).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);
    _isOnline = _hasNetwork(await _connectivity.checkConnectivity());
    _connSub = _connectivity.onConnectivityChanged.listen(_onConnectivity);
    // skip(1): the first event is the current user, start() syncs below.
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
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) syncAll();
  }

  // --------------------------------------------------------------- sync ---

  /// Reload counters/last-sync time and notify. Cheap; safe to call often.
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

  /// Kept for existing callers.
  Future<void> checkPendingChanges() => refreshStatus();

  /// Call after any local write. Updates the badge immediately and schedules
  /// an upload shortly after, only if something is actually waiting (which
  /// also prevents a refresh -> sync -> refresh loop).
  Future<void> notifyLocalChange() async {
    await refreshStatus();
    if (pendingCount == 0) return;
    _debounce?.cancel();
    _debounce = Timer(_writeDebounce, syncAll);
  }

  Future<void> syncAll() async {
    if (_disposed) return;
    if (_isSyncing) {
      _rerun = true; // something changed mid-run; go once more afterwards
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