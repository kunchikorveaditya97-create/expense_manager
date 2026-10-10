// lib/features/dashboard/widgets/sync_status_badge.dart
import 'package:expense_manager/sync/sync_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SyncProvider>();
    final state = p.state;

    final (Color color, IconData icon) = switch (state) {
      SyncUiState.synced => (Colors.green.shade700, Icons.cloud_done),
      SyncUiState.syncing => (Colors.blue.shade700, Icons.sync),
      SyncUiState.pending => (Colors.amber.shade900, Icons.cloud_upload_outlined),
      SyncUiState.offline => (Colors.blueGrey.shade700, Icons.cloud_off),
      SyncUiState.failed => (Colors.red.shade700, Icons.warning_amber_rounded),
      SyncUiState.localOnly => (Colors.grey.shade700, Icons.phone_android),
    };

    return Tooltip(
      message: p.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Tap to retry (no-op while a sync is running).
        onTap: p.isSyncing ? null : () => context.read<SyncProvider>().syncAll(),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state == SyncUiState.syncing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  p.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}