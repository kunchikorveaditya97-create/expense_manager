// lib/data/local/db_key_service.dart
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DbKeyService {
  static const String _storageKey = 'db_encryption_key';

  // The old hardcoded key, kept only to convert existing databases.
  static const String legacyKey = 'expense_manager_secure_local_key';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    await _storage.write(key: _storageKey, value: key);
    return key;
  }
}