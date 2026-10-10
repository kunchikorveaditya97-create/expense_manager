import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/currency_provider.dart';

import 'data/local/app_database.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_nav_scaffold.dart';
import 'providers/auth_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/insights_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transaction_provider.dart';
import 'services/recurring_processor.dart';
import 'sync/sync_provider.dart';
import 'sync/sync_service.dart';
import 'providers/analytics_provider.dart';
import 'providers/category_provider.dart';
import 'providers/account_provider.dart';
import 'providers/goal_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.isAnonymous) {
      await FirebaseAuth.instance.signOut();
    }
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }

  final database = AppDatabase();
  final transactionRepo = TransactionRepositoryImpl(database);
  final budgetRepo = BudgetRepositoryImpl(database);
  final syncService = SyncService(database);

  final transactionProvider = TransactionProvider(transactionRepo);
  final budgetProvider = BudgetProvider(budgetRepo);
  final currencyProvider = CurrencyProvider();
  final insightsProvider = InsightsProvider(database);
  final analyticsProvider = AnalyticsProvider(database);
  final categoryProvider = CategoryProvider(database);
  final goalProvider = GoalProvider(database);
  final accountProvider = AccountProvider(database)
    ..onChanged = transactionProvider.refreshAll;
  insightsProvider.formatAmount = currencyProvider.format;
  currencyProvider.addListener(insightsProvider.generateInsights);

  transactionProvider.onTransactionDataChanged = () {
    final now = DateTime.now();
    budgetProvider.computeMonthlyBudget(now.month, now.year);
    insightsProvider.generateInsights();
    analyticsProvider.load();
  };

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<SyncService>.value(value: syncService),
        ChangeNotifierProvider(create: (_) => AppAuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: currencyProvider),
        ChangeNotifierProvider.value(value: transactionProvider),
        ChangeNotifierProvider.value(value: budgetProvider),
        ChangeNotifierProvider.value(value: insightsProvider),
        ChangeNotifierProvider.value(value: analyticsProvider),
        ChangeNotifierProvider.value(value: categoryProvider),
        ChangeNotifierProvider.value(value: goalProvider),
        ChangeNotifierProvider.value(value: accountProvider),
        ChangeNotifierProvider(create: (_) => SyncProvider(syncService)),
      ],
      child: const ExpenseManagerApp(),
    ),
  );

  RecurringProcessor(database)
      .processDueRecurring()
      .then((_) => transactionProvider.refreshAll())
      .catchError((_) {});
}

class ExpenseManagerApp extends StatelessWidget {
  const ExpenseManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AppAuthProvider>();

    return MaterialApp(
      title: 'Expense Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      // Only authenticated users proceed to dashboard; otherwise show LoginScreen
      home: authProvider.status == AuthStatus.authenticated
          ? const MainNavScaffold()
          : const LoginScreen(),
    );
  }
}