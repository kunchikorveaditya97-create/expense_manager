// lib/services/backup_export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class BackupExportService {
  final AppDatabase _db;

  BackupExportService(this._db);

  // =========================================================================
  // 1. JSON BACKUP EXPORT
  // =========================================================================
  Future<String> exportJsonBackup() async {
    final transactions = await _db.select(_db.transactions).get();
    final accounts = await _db.select(_db.accounts).get();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final List<Map<String, dynamic>> budgets = [];
    final Map<String, dynamic> settings = {};

    for (final key in keys) {
      if (key.startsWith('budget_')) {
        final parts = key.split('_');
        if (parts.length == 3) {
          budgets.add({
            'year': int.tryParse(parts[1]) ?? 0,
            'month': int.tryParse(parts[2]) ?? 0,
            'amount': prefs.getDouble(key) ?? 0.0,
          });
        }
      } else {
        settings[key] = prefs.get(key);
      }
    }

    final backupPayload = {
      "version": 1,
      "exportedAt": DateTime.now().toIso8601String(),
      "transactions": transactions.map((t) => t.toJson()).toList(),
      "categories": [],
      "accounts": accounts.map((a) => a.toJson()).toList(),
      "budgets": budgets,
      "goals": [],
      "settings": settings,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/expense_manager_backup_$timestamp.json');
    await file.writeAsString(jsonString);

    return file.path;
  }

  // =========================================================================
  // 2. JSON BACKUP RESTORE (WITH VALIDATION)
  // =========================================================================
  Future<void> restoreJsonBackup(String jsonContent) async {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid JSON format: root must be an object.');
      }
      payload = decoded;
    } catch (e) {
      throw FormatException('Malformed JSON file: $e');
    }

    final requiredKeys = [
      'version',
      'transactions',
      'categories',
      'accounts',
      'budgets',
      'goals',
      'settings'
    ];
    for (final key in requiredKeys) {
      if (!payload.containsKey(key)) {
        throw FormatException('Validation Error: Missing required key "$key".');
      }
    }

    if (payload['version'] is! int || payload['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }

    final rawTxns = payload['transactions'];
    final rawAccs = payload['accounts'];
    final rawBudgets = payload['budgets'];
    final rawSettings = payload['settings'];

    if (rawTxns is! List || rawAccs is! List || rawBudgets is! List || rawSettings is! Map) {
      throw const FormatException('Validation Error: Schema type mismatch.');
    }

    // Atomic database restore
    await _db.transaction(() async {
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.accounts).go();

      // Restore accounts
      for (final accJson in rawAccs) {
        if (accJson is Map<String, dynamic>) {
          await _db.into(_db.accounts).insert(
            Account(
              id: accJson['id']?.toString() ?? '',
              userId: accJson['userId']?.toString() ?? 'local_user',
              name: accJson['name']?.toString() ?? '',
              type: accJson['type']?.toString() ?? 'regular',
              initialBalance: (accJson['initialBalance'] as num?)?.toDouble() ??
                  (accJson['balance'] as num?)?.toDouble() ??
                  0.0,
              syncStatus: SyncStatus.synced,
              createdAt: DateTime.tryParse(accJson['createdAt']?.toString() ?? '') ?? DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }

      // Restore transactions
      for (final txnJson in rawTxns) {
        if (txnJson is Map<String, dynamic>) {
          final typeVal = txnJson['type'];
          TransactionType parsedType = TransactionType.expense;
          if (typeVal is int && typeVal < TransactionType.values.length) {
            parsedType = TransactionType.values[typeVal];
          } else if (typeVal is String) {
            parsedType = TransactionType.values.firstWhere(
                  (e) => e.name.toLowerCase() == typeVal.toLowerCase(),
              orElse: () => TransactionType.expense,
            );
          }

          await _db.into(_db.transactions).insert(
            Transaction(
              id: txnJson['id']?.toString() ?? '',
              userId: txnJson['userId']?.toString() ?? 'local_user',
              accountId: txnJson['accountId']?.toString() ?? '',
              categoryId: txnJson['categoryId']?.toString() ?? 'General',
              amount: (txnJson['amount'] as num?)?.toDouble() ?? 0.0,
              currency: txnJson['currency']?.toString() ?? 'INR',
              type: parsedType,
              isRecurring: (txnJson['isRecurring'] as bool?) ?? false,
              transactionDate: DateTime.tryParse(txnJson['transactionDate']?.toString() ?? '') ?? DateTime.now(),
              note: txnJson['note']?.toString(),
              syncStatus: SyncStatus.synced,
              createdAt: DateTime.tryParse(txnJson['createdAt']?.toString() ?? '') ?? DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });

    // Restore budgets & settings in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    for (final b in rawBudgets) {
      if (b is Map<String, dynamic>) {
        final year = b['year'];
        final month = b['month'];
        final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
        await prefs.setDouble('budget_${year}_$month', amount);
      }
    }

    for (final entry in rawSettings.entries) {
      if (entry.value is String) {
        await prefs.setString(entry.key, entry.value as String);
      } else if (entry.value is bool) {
        await prefs.setBool(entry.key, entry.value as bool);
      } else if (entry.value is double) {
        await prefs.setDouble(entry.key, entry.value as double);
      } else if (entry.value is int) {
        await prefs.setInt(entry.key, entry.value as int);
      }
    }
  }

  // =========================================================================
  // 3. FILTERED CSV EXPORT
  // Format: Date,Type,Category,Account,Amount,Note
  // =========================================================================
  Future<String> exportFilteredTransactionsCsv({
    int? month,
    int? year,
    TransactionType? type,
    String? categoryId,
    String? accountId,
  }) async {
    final accounts = await _db.select(_db.accounts).get();
    final accNameMap = {for (final a in accounts) a.id: a.name};

    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull());

    if (month != null && year != null) {
      final start = DateTime.utc(year, month, 1);
      final end = DateTime.utc(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
      query.where((t) =>
      t.transactionDate.isBiggerOrEqualValue(start) &
      t.transactionDate.isSmallerOrEqualValue(end));
    }

    if (type != null) {
      query.where((t) => t.type.equalsValue(type));
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      query.where((t) => t.categoryId.equals(categoryId));
    }

    if (accountId != null && accountId.isNotEmpty) {
      query.where((t) => t.accountId.equals(accountId));
    }

    query.orderBy([(t) => OrderingTerm.desc(t.transactionDate)]);
    final txns = await query.get();

    final buffer = StringBuffer();
    buffer.writeln('Date,Type,Category,Account,Amount,Note');

    final dateFormat = DateFormat('yyyy-MM-dd');

    for (final txn in txns) {
      final dateStr = dateFormat.format(txn.transactionDate);
      final typeStr = txn.type == TransactionType.income ? 'Income' : 'Expense';
      final catStr = _escapeCsv(txn.categoryId);
      final accStr = _escapeCsv(accNameMap[txn.accountId] ?? 'Default');
      final amountStr = txn.amount.toStringAsFixed(2);
      final noteStr = _escapeCsv(txn.note ?? '');

      buffer.writeln('$dateStr,$typeStr,$catStr,$accStr,$amountStr,$noteStr');
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/transactions_$timestamp.csv');
    await file.writeAsString(buffer.toString());

    return file.path;
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}