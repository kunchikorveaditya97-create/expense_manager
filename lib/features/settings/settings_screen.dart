import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/backup_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/transaction_provider.dart';
import '../accounts/manage_accounts_screen.dart';
import '../categories/manage_categories_screen.dart';
import '../../providers/category_provider.dart';
import '../../providers/goal_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/auth_provider.dart';
import '../../sync/sync_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currencyProvider = context.watch<CurrencyProvider>();
    final db = context.read<AppDatabase>();
    final backupService = BackupExportService(db);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getThemeIcon(themeProvider.themeMode),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Appearance & Theme',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose how Expense Manager looks to you.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('System'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeProvider.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        themeProvider.setThemeMode(newSelection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(indent: 16, endIndent: 16),

          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & Export'),
            subtitle: const Text('JSON Backup, Restore & Filtered CSV Export'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBackupExportModal(context, backupService),
          ),

          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Manage Accounts'),
            subtitle: const Text('Add, rename or remove accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ManageAccountsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage Categories'),
            subtitle: const Text('Create, restyle or archive categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const ManageCategoriesScreen())),
          ),

          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Default Currency'),
            subtitle: Text(
              '${currencyProvider.current.code} (${currencyProvider.current.symbol})',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCurrencyPicker(context),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Reset Local Data'),
            subtitle: const Text('Deletes all data stored on this device'),
            onTap: () => _confirmResetData(context),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            subtitle: Text(context.watch<AppAuthProvider>().currentUserEmail),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AppAuthProvider>();
    final sync = context.read<SyncProvider>();
    final db = context.read<AppDatabase>();
    final txnProvider = context.read<TransactionProvider>();
    final budgetProvider = context.read<BudgetProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final goalProvider = context.read<GoalProvider>();

    await sync.refreshStatus();
    if (sync.pendingCount > 0) {
      await sync.syncAll();
      await sync.refreshStatus();
    }
    if (!context.mounted) return;

    final pending = sync.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          pending > 0
              ? '$pending change${pending == 1 ? '' : 's'} could not be uploaded '
              '(you may be offline). If you log out now, they will be lost.'
              : 'Your data is synced. It will be removed from this device and '
              'restored when you log back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: pending > 0
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(pending > 0 ? 'Log out anyway' : 'Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await auth.signOut();

    await db.resetAllData();
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs
        .getKeys()
        .where((k) =>
    k.startsWith('budget_') ||
        k.startsWith('sync_cursor_') ||
        k.startsWith('sync_last_'))
        .toList();
    for (final k in stale) {
      await prefs.remove(k);
    }

    await txnProvider.refreshAll();
    await categoryProvider.load();
    await goalProvider.load();
    final now = DateTime.now();
    await budgetProvider.computeMonthlyBudget(now.month, now.year);
  }

  Future<void> _confirmResetData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset local data?'),
        content: const Text(
          'This deletes all transactions, accounts and budgets on this device. '
              'Theme and currency settings stay. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db = context.read<AppDatabase>();
    final txnProvider = context.read<TransactionProvider>();
    final budgetProvider = context.read<BudgetProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final goalProvider = context.read<GoalProvider>();

    await db.resetAllData();

    final prefs = await SharedPreferences.getInstance();
    final budgetKeys =
    prefs.getKeys().where((k) => k.startsWith('budget_')).toList();
    for (final key in budgetKeys) {
      await prefs.remove(key);
    }

    await txnProvider.refreshAll();
    await categoryProvider.load();
    await goalProvider.load();
    final now = DateTime.now();
    await budgetProvider.computeMonthlyBudget(now.month, now.year);

    if (context.mounted) _showSnackBar(context, 'Local data has been reset');
  }

  void _showCurrencyPicker(BuildContext context) {
    final provider = context.read<CurrencyProvider>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: CurrencyProvider.options.map((option) {
            final selected = option.code == provider.current.code;
            return ListTile(
              title: Text('${option.name} (${option.symbol})'),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () {
                provider.setCurrency(option);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showBackupExportModal(BuildContext context, BackupExportService backupService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Data Backup & Export',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, color: Colors.blue),
                title: const Text('Export JSON Backup'),
                subtitle: const Text('Saves all tables, budgets, and settings'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final path = await backupService.exportJsonBackup();
                    await Share.shareXFiles([XFile(path)],
                        text: 'Expense Manager backup');
                  } catch (e) {
                    if (context.mounted) _showSnackBar(context, 'Export failed: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined, color: Colors.orange),
                title: const Text('Restore from JSON Backup'),
                subtitle: const Text('Validates and overwrites local database'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRestoreDialog(context, backupService);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined, color: Colors.green),
                title: const Text('Export Filtered CSV'),
                subtitle: const Text('Export transactions by Month, Year, and Type'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCsvFilterDialog(context, backupService);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCsvFilterDialog(BuildContext context, BackupExportService backupService) {
    int selectedMonth = DateTime.now().month;
    int selectedYear = DateTime.now().year;
    TransactionType? selectedType = TransactionType.expense;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setState) => AlertDialog(
          title: const Text('Filter & Export CSV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selectedMonth,
                decoration: const InputDecoration(labelText: 'Month'),
                items: List.generate(
                  12,
                      (i) => DropdownMenuItem(value: i + 1, child: Text(DateFormat('MMMM').format(DateTime(2026, i + 1)))),
                ),
                onChanged: (v) => setState(() => selectedMonth = v ?? selectedMonth),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: selectedYear,
                decoration: const InputDecoration(labelText: 'Year'),
                items: [2025, 2026, 2027]
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (v) => setState(() => selectedYear = v ?? selectedYear),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<TransactionType?>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Types')),
                  DropdownMenuItem(value: TransactionType.expense, child: Text('Expenses Only')),
                  DropdownMenuItem(value: TransactionType.income, child: Text('Incomes Only')),
                ],
                onChanged: (v) => setState(() => selectedType = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                try {
                  final path = await backupService.exportFilteredTransactionsCsv(
                    month: selectedMonth,
                    year: selectedYear,
                    type: selectedType,
                  );
                  await Share.shareXFiles([XFile(path)],
                      text: 'Expense Manager CSV export');
                } catch (e) {
                  if (context.mounted) _showSnackBar(context, 'CSV Export failed: $e');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestoreDialog(
      BuildContext context, BackupExportService backupService) async {
    final txnProvider = context.read<TransactionProvider>();
    final budgetProvider = context.read<BudgetProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final goalProvider = context.read<GoalProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This replaces all data on this device with the contents of the '
              'backup file. The file is checked first; if it is invalid, nothing changes.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Choose file')),
        ],
      ),
    );
    if (confirmed != true) return;

    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = picked?.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final summary = await backupService.restoreJsonBackup(content);

      await txnProvider.refreshAll();
      await categoryProvider.load();
      await goalProvider.load();
      final now = DateTime.now();
      await budgetProvider.computeMonthlyBudget(now.month, now.year);

      if (context.mounted) _showSnackBar(context, 'Restored: $summary');
    } on FormatException catch (e) {
      if (context.mounted) _showSnackBar(context, 'Invalid backup: ${e.message}');
    } catch (e) {
      if (context.mounted) _showSnackBar(context, 'Restore failed: $e');
    }
  }

  void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }
}