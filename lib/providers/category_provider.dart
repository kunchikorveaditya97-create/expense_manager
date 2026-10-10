import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/category_icons.dart';
import '../data/local/app_database.dart';
import '../data/local/tables.dart';

class CategoryProvider extends ChangeNotifier {
  final AppDatabase _db;
  List<Category> _all = [];

  CategoryProvider(this._db) {
    load();
  }

  List<Category> get all => _all;

  List<Category> forType(TransactionType t) =>
      _all.where((c) => c.type == t).toList();

  List<String> activeNames(TransactionType t) => _all
      .where((c) => c.type == t && !c.isArchived)
      .map((c) => c.name)
      .toList();

  List<String> get allNames => _all.map((c) => c.name).toSet().toList();

  IconData iconFor(String name) {
    for (final c in _all) {
      if (c.name == name) return categoryIcon(c.iconName);
    }
    return Icons.category;
  }

  Future<void> load() async {
    _all = await _db.getAllCategories();
    notifyListeners();
  }

  Future<String?> add(
      String name,
      TransactionType type,
      String iconName,
      int? colorValue,
      ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name';
    if (await _db.categoryNameExists(trimmed, type)) {
      return 'That category already exists';
    }
    await _db.insertCategory(CategoriesCompanion.insert(
      id: const Uuid().v4(),
      userId: 'default_user',
      name: trimmed,
      type: type,
      iconName: iconName,
      colorValue: Value(colorValue),
      isCustom: const Value(true),
      createdAt: DateTime.now().toUtc(),
    ));
    await load();
    return null;
  }

  Future<void> updateStyle(String id, String iconName, int? colorValue) async {
    await _db.updateCategoryStyle(id, iconName, colorValue);
    await load();
  }

  Future<void> setArchived(String id, bool archived) async {
    await _db.setCategoryArchived(id, archived);
    await load();
  }
}