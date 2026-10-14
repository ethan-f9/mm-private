import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_providers.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth_history.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

final allTransfersProvider = StreamProvider<List<Transfer>>(
  (ref) => ref
      .watch(transactionRepositoryProvider)
      .watchTransfersBetween(DateTime(2000), DateTime(2100)),
);

final allPriceSnapshotsProvider = StreamProvider<List<PriceSnapshot>>(
  (ref) => ref.watch(priceRepositoryProvider).watchAll(),
);

final allFxRatesProvider = StreamProvider<List<FxRate>>(
  (ref) => ref.watch(fxRepositoryProvider).watchAllRows(),
);

/// Riwayat net worth harian (IDR), dihitung dari data mentah. Akun yang
/// diarsipkan tidak ikut, sama seperti net worth hari ini.
final netWorthHistoryProvider = Provider<AsyncValue<List<NetWorthPoint>>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final transactions = ref.watch(allTransactionsProvider);
  final transfers = ref.watch(allTransfersProvider);
  final trades = ref.watch(allTradesProvider);
  final assets = ref.watch(assetsProvider);
  final prices = ref.watch(allPriceSnapshotsProvider);
  final fx = ref.watch(allFxRatesProvider);

  for (final value in <AsyncValue<Object?>>[
    accounts, transactions, transfers, trades, assets, prices, fx,
  ]) {
    if (value.hasError) {
      return AsyncValue.error(value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  final a = accounts.valueOrNull;
  final tx = transactions.valueOrNull;
  final tf = transfers.valueOrNull;
  final tr = trades.valueOrNull;
  final as = assets.valueOrNull;
  final pr = prices.valueOrNull;
  final fr = fx.valueOrNull;
  if (a == null || tx == null || tf == null || tr == null || as == null ||
      pr == null || fr == null) {
    return const AsyncValue.loading();
  }

  try {
    return AsyncValue.data(
      computeNetWorthHistory(
        today: DateTime.now(),
        accounts: a,
        transactions: tx,
        transfers: tf,
        trades: tr,
        assets: as,
        prices: pr,
        fxRates: fr,
      ),
    );
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});
