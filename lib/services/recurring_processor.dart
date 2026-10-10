// lib/services/recurring_processor.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class RecurringProcessor {
  final AppDatabase _db;
  final _uuid = const Uuid();

  RecurringProcessor(this._db);

  Future<void> processDueRecurring() async {
    final now = DateTime.now();
    final due = await (_db.select(_db.recurringTransactions)
      ..where((t) => t.isActive.equals(true) & t.nextExecutionDate.isSmallerOrEqualValue(now)))
        .get();

    for (final item in due) {
      await _db.into(_db.transactions).insert(
        TransactionsCompanion.insert(
          id: _uuid.v4(),
          userId: item.userId,
          amount: item.amount,
          type: item.type,
          categoryId: item.categoryId,
          accountId: item.accountId,
          note: Value('Auto-recurring: ${item.note ?? ""}'),
          transactionDate: item.nextExecutionDate,
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pendingCreate,
        ),
      );

      DateTime nextDate = item.nextExecutionDate;
      switch (item.frequency.toLowerCase()) {
        case 'daily':
          nextDate = nextDate.add(const Duration(days: 1));
          break;
        case 'weekly':
          nextDate = nextDate.add(const Duration(days: 7));
          break;
        case 'yearly':
          nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day);
          break;
        case 'monthly':
        default:
          nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
          break;
      }

      await (_db.update(_db.recurringTransactions)..where((t) => t.id.equals(item.id))).write(
        RecurringTransactionsCompanion(
          nextExecutionDate: Value(nextDate),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pendingUpdate),
        ),
      );
    }
  }
}