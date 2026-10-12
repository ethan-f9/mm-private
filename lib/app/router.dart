import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/features/accounts/presentation/add_account_page.dart';
import 'package:personal_finance_manager/features/settings/presentation/settings_page.dart';
import 'package:personal_finance_manager/features/transactions/presentation/add_transaction_page.dart';
import 'package:personal_finance_manager/features/transactions/presentation/add_transfer_page.dart';

import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppShell()),
      GoRoute(
        path: '/add-account',
        builder: (context, state) => const AddAccountPage(),
      ),
      GoRoute(
        path: '/add-transaction',
        builder: (context, state) => const AddTransactionPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/add-transfer',
        builder: (context, state) => const AddTransferPage(),
      ),
    ],
  );
});
