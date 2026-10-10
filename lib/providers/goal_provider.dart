import 'package:flutter/foundation.dart';
import '../data/local/app_database.dart';

class GoalProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<SavingsGoal> _goals = [];

  GoalProvider(this._db) {
    load();
  }

  List<SavingsGoal> get goals => _goals;

  Future<void> load() async {
    _goals = await _db.getAllGoals();
    notifyListeners();
  }

  Future<void> add(String name, double target, double saved, DateTime date,
      String icon) async {
    await _db.insertGoal(name, target, saved, date, icon);
    await load();
  }

  Future<void> update(String id, String name, double target, DateTime date,
      String icon) async {
    await _db.updateGoalDetails(id, name, target, date, icon);
    await load();
  }

  /// Negative delta withdraws.
  Future<void> addFunds(String id, double delta) async {
    await _db.adjustGoalAmount(id, delta);
    await load();
  }

  Future<void> delete(String id) async {
    await _db.softDeleteGoal(id);
    await load();
  }
}