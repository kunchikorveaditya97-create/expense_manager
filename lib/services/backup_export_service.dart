import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class BackupExportService {
  final AppDatabase _db;

  BackupExportService(this._db);

  static const _frequencies = {'daily', 'weekly', 'monthly', 'yearly'};

  String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.tryParse(v.toString());
  }

  String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  TransactionType? _type(dynamic v) {
    if (v is int && v >= 0 && v < TransactionType.values.length) {
      return TransactionType.values[v];
    }
    if (v is String) {
      for (final t in TransactionType.values) {
        if (t.name == v.toLowerCase()) return t;
      }
    }
    return null;
  }

  Future<String> exportJsonBackup() async {
    final txns = await _db.select(_db.transactions).get();
    final accs = await _db.select(_db.accounts).get();
    final cats = await _db.select(_db.categories).get();
    final buds = await _db.select(_db.budgets).get();
    final goals = await _db.select(_db.savingsGoals).get();
    final recs = await _db.select(_db.recurringTransactions).get();

    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('budget_')) continue;
      settings[key] = prefs.get(key);
    }

    final payload = {
      'version': 1,
      'exportedAt': _iso(DateTime.now()),
      'transactions': [
        for (final t in txns)
          {
            'id': t.id,
            'userId': t.userId,
            'amount': t.amount,
            'type': t.type.name,
            'categoryId': t.categoryId,
            'accountId': t.accountId,
            'note': t.note,
            'transactionDate': _iso(t.transactionDate),
            'attachmentPath': t.attachmentPath,
            'isRecurring': t.isRecurring,
            'currency': t.currency,
            'createdAt': _iso(t.createdAt),
            'updatedAt': _iso(t.updatedAt),
            'deletedAt': _iso(t.deletedAt),
          }
      ],
      'categories': [
        for (final c in cats)
          {
            'id': c.id,
            'userId': c.userId,
            'name': c.name,
            'type': c.type.name,
            'iconName': c.iconName,
            'colorValue': c.colorValue,
            'isArchived': c.isArchived,
            'isCustom': c.isCustom,
            'createdAt': _iso(c.createdAt),
          }
      ],
      'accounts': [
        for (final a in accs)
          {
            'id': a.id,
            'userId': a.userId,
            'name': a.name,
            'type': a.type,
            'initialBalance': a.initialBalance,
            'createdAt': _iso(a.createdAt),
            'updatedAt': _iso(a.updatedAt),
            'deletedAt': _iso(a.deletedAt),
          }
      ],
      'budgets': [
        for (final b in buds)
          {
            'id': b.id,
            'categoryId': b.categoryId,
            'limitAmount': b.limitAmount,
            'month': b.month,
            'year': b.year,
          }
      ],
      'goals': [
        for (final g in goals)
          {
            'id': g.id,
            'userId': g.userId,
            'name': g.name,
            'targetAmount': g.targetAmount,
            'currentAmount': g.currentAmount,
            'targetDate': _iso(g.targetDate),
            'iconName': g.iconName,
            'createdAt': _iso(g.createdAt),
            'updatedAt': _iso(g.updatedAt),
            'deletedAt': _iso(g.deletedAt),
          }
      ],
      'recurring': [
        for (final r in recs)
          {
            'id': r.id,
            'userId': r.userId,
            'amount': r.amount,
            'type': r.type.name,
            'categoryId': r.categoryId,
            'accountId': r.accountId,
            'note': r.note,
            'frequency': r.frequency,
            'nextExecutionDate': _iso(r.nextExecutionDate),
            'isActive': r.isActive,
            'createdAt': _iso(r.createdAt),
            'updatedAt': _iso(r.updatedAt),
            'deletedAt': _iso(r.deletedAt),
          }
      ],
      'settings': settings,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/expense_manager_backup_$timestamp.json');
    await file.writeAsString(jsonString);
    return file.path;
  }

  Future<String> restoreJsonBackup(String jsonContent) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } catch (_) {
      throw const FormatException('The file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The root of the file must be a JSON object.');
    }
    final payload = decoded;

    for (final key in ['version', 'transactions', 'accounts']) {
      if (!payload.containsKey(key)) {
        throw FormatException('Missing required key "$key".');
      }
    }
    if (payload['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }

    List<Map<String, dynamic>> list(String key) {
      final raw = payload[key];
      if (raw == null) return [];
      if (raw is! List) throw FormatException('"$key" must be a list.');
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map<String, dynamic>) {
          throw FormatException('"$key" item #${i + 1} is not an object.');
        }
        out.add(item);
      }
      return out;
    }

    final settingsRaw = payload['settings'];
    if (settingsRaw != null && settingsRaw is! Map) {
      throw const FormatException('"settings" must be an object.');
    }

    final now = DateTime.now().toUtc();
    const uuid = Uuid();

    final accountRows = <AccountsCompanion>[];
    final accountIds = <String>{};
    final nameToId = <String, String>{};
    final accJson = list('accounts');
    for (var i = 0; i < accJson.length; i++) {
      final a = accJson[i];
      final id = _str(a['id']);
      final name = _str(a['name']);
      if (id == null || name == null) {
        throw FormatException('Account #${i + 1} needs an id and a name.');
      }
      accountIds.add(id);
      nameToId[name] = id;
      accountRows.add(AccountsCompanion(
        id: Value(id),
        userId: Value(_str(a['userId']) ?? 'default_user'),
        name: Value(name),
        type: Value(_str(a['type']) ?? 'cash'),
        initialBalance: Value((a['initialBalance'] as num?)?.toDouble() ??
            (a['balance'] as num?)?.toDouble() ??
            0.0),
        createdAt: Value(_dt(a['createdAt']) ?? now),
        updatedAt: Value(_dt(a['updatedAt']) ?? now),
        deletedAt: Value(_dt(a['deletedAt'])),
        syncStatus: const Value(SyncStatus.synced),
      ));
    }

    final categoryRows = <CategoriesCompanion>[];
    final catJson = list('categories');
    for (var i = 0; i < catJson.length; i++) {
      final c = catJson[i];
      final id = _str(c['id']);
      final name = _str(c['name']);
      final type = _type(c['type']);
      if (id == null || name == null || type == null) {
        throw FormatException(
            'Category #${i + 1} needs an id, a name and a valid type.');
      }
      categoryRows.add(CategoriesCompanion(
        id: Value(id),
        userId: Value(_str(c['userId']) ?? 'default_user'),
        name: Value(name),
        type: Value(type),
        iconName: Value(_str(c['iconName']) ?? 'category'),
        colorValue: Value((c['colorValue'] as num?)?.toInt()),
        isArchived: Value(c['isArchived'] == true),
        isCustom: Value(c['isCustom'] == true),
        createdAt: Value(_dt(c['createdAt']) ?? now),
      ));
    }

    final txnRows = <TransactionsCompanion>[];
    final txnJson = list('transactions');
    for (var i = 0; i < txnJson.length; i++) {
      final t = txnJson[i];
      final id = _str(t['id']);
      final type = _type(t['type']);
      final date = _dt(t['transactionDate']);
      final amount = t['amount'] as num?;
      final cat = _str(t['categoryId']);
      final accRaw = _str(t['accountId']);
      if (id == null ||
          type == null ||
          date == null ||
          amount == null ||
          amount < 0 ||
          cat == null ||
          accRaw == null) {
        throw FormatException(
            'Transaction #${i + 1} is missing a field or has an invalid value.');
      }
      final accId = accountIds.contains(accRaw) ? accRaw : nameToId[accRaw];
      if (accId == null) {
        throw FormatException(
            'Transaction #${i + 1} references an account that is not in the backup.');
      }
      final deleted = _dt(t['deletedAt']);
      txnRows.add(TransactionsCompanion(
        id: Value(id),
        userId: Value(_str(t['userId']) ?? 'default_user'),
        amount: Value(amount.toDouble()),
        type: Value(type),
        categoryId: Value(cat),
        accountId: Value(accId),
        note: Value(_str(t['note'])),
        transactionDate: Value(date),
        attachmentPath: Value(_str(t['attachmentPath'])),
        isRecurring: Value(t['isRecurring'] == true),
        currency: Value(_str(t['currency']) ?? 'INR'),
        createdAt: Value(_dt(t['createdAt']) ?? now),
        updatedAt: Value(now),
        deletedAt: Value(deleted),
        syncStatus: Value(deleted != null
            ? SyncStatus.pendingDelete
            : SyncStatus.pendingCreate),
      ));
    }

    final budgetRows = <BudgetsCompanion>[];
    final budJson = list('budgets');
    for (var i = 0; i < budJson.length; i++) {
      final b = budJson[i];
      final month = (b['month'] as num?)?.toInt();
      final year = (b['year'] as num?)?.toInt();
      final limit = (b['limitAmount'] ?? b['amount']) as num?;
      if (month == null ||
          month < 1 ||
          month > 12 ||
          year == null ||
          limit == null ||
          limit < 0) {
        throw FormatException('Budget #${i + 1} has an invalid month, year or amount.');
      }
      budgetRows.add(BudgetsCompanion(
        id: Value(_str(b['id']) ?? uuid.v4()),
        categoryId: Value(_str(b['categoryId']) ?? 'ALL'),
        limitAmount: Value(limit.toDouble()),
        month: Value(month),
        year: Value(year),
        syncStatus: const Value(SyncStatus.synced),
      ));
    }

    final goalRows = <SavingsGoalsCompanion>[];
    final goalJson = list('goals');
    for (var i = 0; i < goalJson.length; i++) {
      final g = goalJson[i];
      final id = _str(g['id']);
      final name = _str(g['name']);
      final target = g['targetAmount'] as num?;
      final date = _dt(g['targetDate']);
      if (id == null || name == null || target == null || target <= 0 || date == null) {
        throw FormatException('Goal #${i + 1} is missing a field or has an invalid value.');
      }
      goalRows.add(SavingsGoalsCompanion(
        id: Value(id),
        userId: Value(_str(g['userId']) ?? 'default_user'),
        name: Value(name),
        targetAmount: Value(target.toDouble()),
        currentAmount: Value(((g['currentAmount'] as num?)?.toDouble() ?? 0.0)),
        targetDate: Value(date),
        iconName: Value(_str(g['iconName']) ?? 'savings'),
        createdAt: Value(_dt(g['createdAt']) ?? now),
        updatedAt: Value(now),
        deletedAt: Value(_dt(g['deletedAt'])),
        syncStatus: const Value(SyncStatus.synced),
      ));
    }

    final recurringRows = <RecurringTransactionsCompanion>[];
    final recJson = list('recurring');
    for (var i = 0; i < recJson.length; i++) {
      final r = recJson[i];
      final id = _str(r['id']);
      final type = _type(r['type']);
      final amount = r['amount'] as num?;
      final cat = _str(r['categoryId']);
      final accRaw = _str(r['accountId']);
      final next = _dt(r['nextExecutionDate']);
      final freq = _str(r['frequency'])?.toLowerCase();
      if (id == null ||
          type == null ||
          amount == null ||
          cat == null ||
          accRaw == null ||
          next == null ||
          freq == null ||
          !_frequencies.contains(freq)) {
        throw FormatException(
            'Recurring item #${i + 1} is missing a field or has an invalid value.');
      }
      final accId = accountIds.contains(accRaw) ? accRaw : nameToId[accRaw];
      if (accId == null) {
        throw FormatException(
            'Recurring item #${i + 1} references an account that is not in the backup.');
      }
      recurringRows.add(RecurringTransactionsCompanion(
        id: Value(id),
        userId: Value(_str(r['userId']) ?? 'default_user'),
        amount: Value(amount.toDouble()),
        type: Value(type),
        categoryId: Value(cat),
        accountId: Value(accId),
        note: Value(_str(r['note'])),
        frequency: Value(freq),
        nextExecutionDate: Value(next),
        isActive: Value(r['isActive'] != false),
        createdAt: Value(_dt(r['createdAt']) ?? now),
        updatedAt: Value(now),
        deletedAt: Value(_dt(r['deletedAt'])),
        syncStatus: const Value(SyncStatus.pendingCreate),
      ));
    }

    await _db.replaceAllData(
      accountRows: accountRows,
      categoryRows: categoryRows,
      transactionRows: txnRows,
      budgetRows: budgetRows,
      goalRows: goalRows,
      recurringRows: recurringRows,
    );

    final prefs = await SharedPreferences.getInstance();
    final oldBudgetKeys =
    prefs.getKeys().where((k) => k.startsWith('budget_')).toList();
    for (final k in oldBudgetKeys) {
      await prefs.remove(k);
    }
    if (settingsRaw is Map) {
      for (final entry in settingsRaw.entries) {
        final key = entry.key.toString();
        final v = entry.value;
        if (key.startsWith('budget_')) continue;
        if (v is String) {
          await prefs.setString(key, v);
        } else if (v is bool) {
          await prefs.setBool(key, v);
        } else if (v is int) {
          await prefs.setInt(key, v);
        } else if (v is double) {
          await prefs.setDouble(key, v);
        } else if (v is List && v.every((e) => e is String)) {
          await prefs.setStringList(key, v.cast<String>());
        }
      }
    }

    return '${txnRows.length} transactions, ${accountRows.length} accounts, '
        '${categoryRows.length} categories, ${budgetRows.length} budgets, '
        '${goalRows.length} goals';
  }

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
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      query.where((t) =>
      t.transactionDate.isBiggerOrEqualValue(start) &
      t.transactionDate.isSmallerThanValue(end));
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
      final accStr = _escapeCsv(accNameMap[txn.accountId] ?? txn.accountId);
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