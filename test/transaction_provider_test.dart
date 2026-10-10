import 'package:drift/drift.dart' show Value;
import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/local/tables.dart';
import 'package:expense_manager/data/repositories/transaction_repository.dart';
import 'package:expense_manager/providers/transaction_provider.dart';
import 'package:flutter_test/flutter_test.dart';

final _d = DateTime(2026, 10, 1);

Transaction tx(
    String id, {
      double amount = 10,
      TransactionType type = TransactionType.expense,
      String categoryId = 'Food',
      DateTime? date,
    }) =>
    Transaction(
      id: id,
      userId: 'u1',
      amount: amount,
      type: type,
      categoryId: categoryId,
      accountId: 'acc1',
      note: null,
      transactionDate: date ?? _d,
      attachmentPath: null,
      isRecurring: false,
      currency: 'INR',
      fieldTimestamps: null,
      createdAt: _d,
      updatedAt: _d,
      deletedAt: null,
      syncStatus: SyncStatus.synced,
    );

final cashAccount = Account(
  id: 'acc1',
  userId: 'u1',
  name: 'Cash',
  type: 'cash',
  initialBalance: 0,
  createdAt: _d,
  updatedAt: _d,
  deletedAt: null,
  syncStatus: SyncStatus.synced,
);

class FakeTransactionRepository implements ITransactionRepository {
  FakeTransactionRepository({
    List<Transaction>? seed,
    List<Account>? accounts,
    this.queryDelay = Duration.zero,
  })  : rows = [...?seed],
        accounts = accounts ?? [cashAccount];

  final List<Transaction> rows;
  final List<Account> accounts;
  final Duration queryDelay;

  final List<TransactionsCompanion> inserted = [];
  final List<String> softDeleted = [];

  @override
  Future<int> insertTransaction(TransactionsCompanion c) async {
    inserted.add(c);
    rows.insert(
      0,
      Transaction(
        id: c.id.value,
        userId: c.userId.value,
        amount: c.amount.value,
        type: c.type.value,
        categoryId: c.categoryId.value,
        accountId: c.accountId.value,
        note: c.note.present ? c.note.value : null,
        transactionDate: c.transactionDate.value,
        attachmentPath: null,
        isRecurring: false,
        currency: 'INR',
        fieldTimestamps: null,
        createdAt: c.createdAt.value,
        updatedAt: c.updatedAt.value,
        deletedAt: null,
        syncStatus: c.syncStatus.value,
      ),
    );
    return 1;
  }

  @override
  Future<bool> updateTransaction(TransactionsCompanion c) async => true;

  @override
  Future<int> softDeleteTransaction(String id) async {
    softDeleted.add(id);
    rows.removeWhere((t) => t.id == id);
    return 1;
  }

  @override
  Future<int> restoreTransaction(String id) async => 1;

  @override
  Future<List<Transaction>> getPaginatedTransactions({
    required int limit,
    required int offset,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? searchQuery,
  }) async {
    if (queryDelay > Duration.zero) await Future.delayed(queryDelay);
    final filtered = rows
        .where((t) => type == null || t.type == type)
        .where((t) => categoryId == null || t.categoryId == categoryId)
        .toList();
    return filtered.skip(offset).take(limit).toList();
  }

  double _sum(TransactionType type) => rows
      .where((t) => t.type == type)
      .fold(0.0, (s, t) => s + t.amount);

  @override
  Future<double> getTotalIncome() async => _sum(TransactionType.income);

  @override
  Future<double> getTotalExpense() async => _sum(TransactionType.expense);

  @override
  Future<double> getMonthTotal(TransactionType type, int month, int year) async =>
      rows
          .where((t) =>
      t.type == type &&
          t.transactionDate.month == month &&
          t.transactionDate.year == year)
          .fold<double>(0.0, (s, t) => s + t.amount);

  @override
  Future<int> getAccountCount() async => accounts.length;

  @override
  Future<List<Account>> getAllAccounts() async => accounts;

  @override
  Future<Map<String, double>> getAccountBalances() async => {
    for (final a in accounts)
      a.id: a.initialBalance +
          rows
              .where((t) => t.accountId == a.id)
              .fold<double>(
              0.0,
                  (s, t) =>
              s +
                  (t.type == TransactionType.income
                      ? t.amount
                      : -t.amount)),
  };

  @override
  Future<void> insertRecurring(RecurringTransactionsCompanion c) async {}
}

Future<TransactionProvider> makeProvider(FakeTransactionRepository repo) async {
  final p = TransactionProvider(repo);
  await pumpEventQueue();
  return p;
}

void main() {
  group('balance calculations', () {
    test('total balance = total income - total expenses', () async {
      final repo = FakeTransactionRepository(seed: [
        tx('a', amount: 2500, type: TransactionType.income),
        tx('b', amount: 400),
        tx('c', amount: 100),
      ]);
      final p = await makeProvider(repo);

      expect(p.totalIncome, 2500);
      expect(p.totalExpense, 500);
      expect(p.totalBalance, 2000);
    });

    test('month totals only count the current month', () async {
      final now = DateTime.now();
      final lastYear = DateTime(now.year - 1, now.month, 5);
      final repo = FakeTransactionRepository(seed: [
        tx('a', amount: 300, date: now),
        tx('b', amount: 999, date: lastYear),
      ]);
      final p = await makeProvider(repo);

      expect(p.monthExpense, 300);
      expect(p.totalExpense, 1299);
    });

    test('with no accounts, all totals read as zero', () async {
      final repo = FakeTransactionRepository(
        seed: [tx('a', amount: 100)],
        accounts: [],
      );
      final p = await makeProvider(repo);

      expect(p.hasAccounts, isFalse);
      expect(p.totalBalance, 0);
      expect(p.totalExpense, 0);
    });

    test('balance updates after deleting a transaction', () async {
      final repo = FakeTransactionRepository(seed: [
        tx('a', amount: 1000, type: TransactionType.income),
        tx('b', amount: 250),
      ]);
      final p = await makeProvider(repo);
      expect(p.totalBalance, 750);

      await p.deleteTransaction('b');

      expect(p.totalBalance, 1000);
      expect(p.transactions.map((t) => t.id), ['a']);
      expect(repo.softDeleted, ['b']);
    });
  });

  group('create / update', () {
    test('createTransaction stores a positive amount and marks pendingCreate',
            () async {
          final repo = FakeTransactionRepository();
          final p = await makeProvider(repo);

          await p.createTransaction(
            userId: 'u1',
            amount: -75,
            type: TransactionType.expense,
            categoryId: 'Food',
            accountId: 'acc1',
            note: 'Lunch',
            transactionDate: DateTime(2026, 10, 2),
          );

          final c = repo.inserted.single;
          expect(c.amount, const Value(75.0));
          expect(c.syncStatus.value, SyncStatus.pendingCreate);
          expect(p.transactions.length, 1);
          expect(p.totalExpense, 75);
        });

    test('notifies listeners when data changes', () async {
      final repo = FakeTransactionRepository();
      final p = await makeProvider(repo);
      var changed = 0;
      p.onTransactionDataChanged = () => changed++;

      await p.createTransaction(
        userId: 'u1',
        amount: 10,
        type: TransactionType.income,
        categoryId: 'Salary',
        accountId: 'acc1',
        transactionDate: DateTime(2026, 10, 2),
      );

      expect(changed, greaterThan(0));
    });
  });

  group('pagination', () {
    test('loads 20 at a time and stops when exhausted', () async {
      final repo = FakeTransactionRepository(
        seed: [for (var i = 0; i < 45; i++) tx('id$i')],
      );
      final p = await makeProvider(repo);

      expect(p.transactions.length, 20);
      expect(p.hasMore, isTrue);

      await p.fetchMore();
      expect(p.transactions.length, 40);

      await p.fetchMore();
      expect(p.transactions.length, 45);
      expect(p.hasMore, isFalse);
    });

    test('overlapping refreshes never produce duplicate rows', () async {
      final repo = FakeTransactionRepository(
        seed: [for (var i = 0; i < 5; i++) tx('id$i')],
        queryDelay: const Duration(milliseconds: 20),
      );
      final p = TransactionProvider(repo);

      final r1 = p.refreshAll();
      final r2 = p.refreshAll();
      await Future.wait([r1, r2]);
      await pumpEventQueue();

      final ids = p.transactions.map((t) => t.id).toList();
      expect(ids.length, ids.toSet().length, reason: 'duplicate ids: $ids');
      expect(ids.length, 5);
    });
  });

  group('filters', () {
    test('type filter only returns matching transactions', () async {
      final repo = FakeTransactionRepository(seed: [
        tx('a', type: TransactionType.income, categoryId: 'Salary'),
        tx('b'),
        tx('c'),
      ]);
      final p = await makeProvider(repo);

      p.setFilters(type: TransactionType.expense);
      await pumpEventQueue();

      expect(p.transactions.map((t) => t.id), ['b', 'c']);
      expect(p.hasActiveFilters, isTrue);
    });

    test('combined filters (expense + category)', () async {
      final repo = FakeTransactionRepository(seed: [
        tx('a', categoryId: 'Food'),
        tx('b', categoryId: 'Travel'),
        tx('c', type: TransactionType.income, categoryId: 'Food'),
      ]);
      final p = await makeProvider(repo);

      p.setFilters(type: TransactionType.expense, categoryId: 'Food');
      await pumpEventQueue();

      expect(p.transactions.map((t) => t.id), ['a']);
    });

    test('clearFilters restores the full list', () async {
      final repo = FakeTransactionRepository(seed: [
        tx('a', type: TransactionType.income),
        tx('b'),
      ]);
      final p = await makeProvider(repo);

      p.setFilters(type: TransactionType.income);
      await pumpEventQueue();
      expect(p.transactions.length, 1);

      p.clearFilters();
      await pumpEventQueue();
      expect(p.transactions.length, 2);
      expect(p.hasActiveFilters, isFalse);
    });
  });
}