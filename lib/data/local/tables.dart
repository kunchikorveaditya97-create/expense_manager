// lib/data/local/tables.dart
import 'package:drift/drift.dart';

enum TransactionType { income, expense }
enum SyncStatus { synced, pendingCreate, pendingUpdate, pendingDelete, failed }

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  RealColumn get amount => real()();
  IntColumn get type => intEnum<TransactionType>()();
  TextColumn get categoryId => text()();
  TextColumn get accountId => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get attachmentPath => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get fieldTimestamps => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // cash, bank, credit_card, savings
  RealColumn get initialBalance => real().withDefault(const Constant(0.0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()(); // 'ALL' or specific category name
  RealColumn get limitAmount => real()();
  IntColumn get month => integer()();
  IntColumn get year => integer()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentAmount => real().withDefault(const Constant(0.0))();
  DateTimeColumn get targetDate => dateTime()();
  TextColumn get iconName => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

class RecurringTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  RealColumn get amount => real()();
  IntColumn get type => intEnum<TransactionType>()();
  TextColumn get categoryId => text()();
  TextColumn get accountId => text()();
  TextColumn get note => text().nullable()();
  TextColumn get frequency => text()(); // daily, weekly, monthly, yearly
  DateTimeColumn get nextExecutionDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get type => intEnum<TransactionType>()();
  TextColumn get iconName => text()();
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}