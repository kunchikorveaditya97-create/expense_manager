import 'package:flutter/foundation.dart';
import '../data/local/app_database.dart';

/// Account actions. The account list itself lives in TransactionProvider.
class AccountProvider extends ChangeNotifier {
  final AppDatabase _db;
  VoidCallback? onChanged;

  AccountProvider(this._db);

  Future<void> add(String name, String type, double initialBalance) async {
    await _db.insertAccount(name.trim(), type, initialBalance);
    onChanged?.call();
  }

  Future<void> update(String id, String name, double initialBalance) async {
    await _db.updateAccountDetails(id, name.trim(), initialBalance);
    onChanged?.call();
  }

  /// False if the account still has transactions.
  Future<bool> deleteIfUnused(String id) async {
    final ok = await _db.deleteAccountIfUnused(id);
    if (ok) onChanged?.call();
    return ok;
  }
}