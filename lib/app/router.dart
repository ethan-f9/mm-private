import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/accounts/presentation/add_account_page.dart';
import 'package:personal_finance_manager/features/advisor/presentation/advisor_page.dart';
import 'package:personal_finance_manager/features/advisor/presentation/allocation_targets_page.dart';
import 'package:personal_finance_manager/features/backup/presentation/backup_page.dart';
import 'package:personal_finance_manager/features/investments/presentation/add_asset_page.dart';
import 'package:personal_finance_manager/features/investments/presentation/add_trade_page.dart';
import 'package:personal_finance_manager/features/investments/presentation/asset_detail_page.dart';
import 'package:personal_finance_manager/features/investments/presentation/update_prices_page.dart';
import 'package:personal_finance_manager/features/settings/presentation/settings_page.dart';
import 'package:personal_finance_manager/features/templates/presentation/templates_page.dart';
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
        path: '/edit-transaction',
        builder: (context, state) =>
            AddTransactionPage(existing: state.extra as TransactionRow?),
      ),
      // '/assets/new' harus sebelum '/assets/:id' (yang cocok pertama dipakai).
      GoRoute(
        path: '/assets/new',
        builder: (context, state) => const AddAssetPage(),
      ),
      GoRoute(
        path: '/assets/:id',
        builder: (context, state) =>
            AssetDetailPage(assetId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/assets/:id/trade',
        builder: (context, state) =>
            AddTradePage(assetId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/prices',
        builder: (context, state) => const UpdatePricesPage(),
      ),
      GoRoute(
        path: '/advisor',
        builder: (context, state) => const AdvisorPage(),
      ),
      GoRoute(
        path: '/allocation',
        builder: (context, state) => const AllocationTargetsPage(),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupPage(),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TemplatesPage(),
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
