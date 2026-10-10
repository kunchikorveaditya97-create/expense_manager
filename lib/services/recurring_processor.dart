import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

DateTime nextRecurrence(DateTime d, String frequency) {
  switch (frequency.toLowerCase()) {
    case 'daily':
      return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
    case 'weekly':
      return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
    case 'yearly':
      return _addMonths(d, 12);
    case 'monthly':
    default:
      return _addMonths(d, 1);
  }
}

DateTime _addMonths(DateTime d, int n) {
  final total = d.month - 1 + n;
  final y = d.year + total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

class RecurringProcessor {
  final AppDatabase _db;
  final _uuid = const Uuid();

  RecurringProcessor(this._db);

  Future<void> processDueRecurring() async {
    final now = DateTime.now();
    final due = await (_db.select(_db.recurringTransactions)
      ..where((t) =>
      t.isActive.equals(true) &
      t.deletedAt.isNull() &
      t.nextExecutionDate.isSmallerOrEqualValue(now)))
        .get();

    for (final item in due) {
      var next = item.nextExecutionDate;

      while (!next.isAfter(now)) {
        await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: _uuid.v4(),
            userId: item.userId,
            amount: item.amount,
            type: item.type,
            categoryId: item.categoryId,
            accountId: item.accountId,
            note: Value('Auto-recurring: ${item.note ?? ""}'),
            transactionDate: next,
            isRecurring: const Value(true),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
            syncStatus: SyncStatus.pendingCreate,
          ),
        );
        next = nextRecurrence(next, item.frequency);
      }

      await (_db.update(_db.recurringTransactions)
        ..where((t) => t.id.equals(item.id)))
          .write(
        RecurringTransactionsCompanion(
          nextExecutionDate: Value(next),
          updatedAt: Value(now.toUtc()),
          syncStatus: const Value(SyncStatus.pendingUpdate),
        ),
      );
    }
  }
}