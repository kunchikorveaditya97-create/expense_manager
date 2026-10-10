import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyOption {
  final String code;
  final String symbol;
  final String name;
  const CurrencyOption(this.code, this.symbol, this.name);
}

class CurrencyProvider extends ChangeNotifier {
  static const String _prefKey = 'selected_currency_code';

  static const List<CurrencyOption> options = [
    CurrencyOption('INR', '₹', 'Indian Rupee'),
    CurrencyOption('USD', '\$', 'US Dollar'),
    CurrencyOption('EUR', '€', 'Euro'),
    CurrencyOption('GBP', '£', 'British Pound'),
  ];

  CurrencyOption _current = options.first;

  CurrencyProvider() {
    _load();
  }

  CurrencyOption get current => _current;

  NumberFormat get formatter =>
      NumberFormat.currency(symbol: _current.symbol, decimalDigits: 2);

  String format(double amount) => formatter.format(amount);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    _current = options.firstWhere(
          (o) => o.code == code,
      orElse: () => options.first,
    );
    notifyListeners();
  }

  Future<void> setCurrency(CurrencyOption option) async {
    if (_current.code == option.code) return;
    _current = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, option.code);
  }
}