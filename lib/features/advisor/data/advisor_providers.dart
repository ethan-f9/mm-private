import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_repository.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_service.dart';
import 'package:personal_finance_manager/features/advisor/data/allocation_repository.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

final allocationRepositoryProvider = Provider<AllocationRepository>(
  (ref) => AllocationRepository(ref.watch(appDatabaseProvider)),
);

final advisorRepositoryProvider = Provider<AdvisorRepository>(
  (ref) => AdvisorRepository(ref.watch(appDatabaseProvider)),
);

final allocationTargetsProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(allocationRepositoryProvider).watch(),
);

final latestAdvisorProvider = StreamProvider<AdvisorInsight?>(
  (ref) => ref.watch(advisorRepositoryProvider).watchLatest(),
);

/// Seluruh transaksi (dibutuhkan untuk rentang data dan tren).
final allTransactionsProvider = StreamProvider<List<TransactionRow>>(
  (ref) => ref
      .watch(transactionRepositoryProvider)
      .watchBetween(DateTime(2000), DateTime(2100)),
);

final advisorMetricsProvider = Provider<AsyncValue<AdvisorMetrics>>((ref) {
  final transactions = ref.watch(allTransactionsProvider);
  final categories = ref.watch(categoriesProvider);
  final netWorth = ref.watch(netWorthProvider);
  final holdings = ref.watch(holdingsProvider);
  final fx = ref.watch(fxTableProvider);
  final targets = ref.watch(allocationTargetsProvider);

  for (final value in <AsyncValue<Object?>>[
    transactions, categories, netWorth, holdings, fx, targets,
  ]) {
    if (value.hasError) {
      return AsyncValue.error(value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  final tx = transactions.valueOrNull;
  final cat = categories.valueOrNull;
  final nw = netWorth.valueOrNull;
  final hold = holdings.valueOrNull;
  final fxTable = fx.valueOrNull ?? FxTable.empty;
  final target = targets.valueOrNull;
  if (tx == null || cat == null || nw == null || hold == null || target == null) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    computeAdvisorMetrics(
      now: DateTime.now(),
      transactions: tx,
      categoryNames: {for (final c in cat) c.id: c.name},
      netWorth: nw,
      holdings: hold,
      fx: fxTable,
      targetBps: target,
    ),
  );
});

final advisorServiceProvider = Provider<AdvisorService>(
  (ref) => AdvisorService(
    llm: ref.watch(llmClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
    repository: ref.watch(advisorRepositoryProvider),
  ),
);
