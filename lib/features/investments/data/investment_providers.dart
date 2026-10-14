import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/investments/data/asset_repository.dart';
import 'package:personal_finance_manager/features/investments/data/fx_repository.dart';
import 'package:personal_finance_manager/features/investments/data/price_repository.dart';
import 'package:personal_finance_manager/features/investments/data/trade_repository.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';

final assetRepositoryProvider =
    Provider<AssetRepository>((ref) => AssetRepository(ref.watch(appDatabaseProvider)));
final tradeRepositoryProvider =
    Provider<TradeRepository>((ref) => TradeRepository(ref.watch(appDatabaseProvider)));
final priceRepositoryProvider =
    Provider<PriceRepository>((ref) => PriceRepository(ref.watch(appDatabaseProvider)));
final fxRepositoryProvider =
    Provider<FxRepository>((ref) => FxRepository(ref.watch(appDatabaseProvider)));

final assetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(assetRepositoryProvider).watchAll(),
);

final allTradesProvider = StreamProvider<List<Trade>>(
  (ref) => ref.watch(tradeRepositoryProvider).watchAll(),
);

final latestPricesProvider = StreamProvider<Map<String, PriceSnapshot>>(
  (ref) => ref.watch(priceRepositoryProvider).watchLatest(),
);

final fxTableProvider = StreamProvider<FxTable>(
  (ref) => ref.watch(fxRepositoryProvider).watchLatest(),
);

/// Posisi semua aset (average cost + harga terakhir).
final holdingsProvider = Provider<AsyncValue<List<Holding>>>((ref) {
  final assets = ref.watch(assetsProvider);
  final trades = ref.watch(allTradesProvider);
  final prices = ref.watch(latestPricesProvider);

  for (final value in [assets, trades, prices]) {
    if (value.hasError) {
      return AsyncValue.error(value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  final a = assets.valueOrNull;
  final t = trades.valueOrNull;
  final p = prices.valueOrNull;
  if (a == null || t == null || p == null) return const AsyncValue.loading();

  try {
    return AsyncValue.data(buildHoldings(a, t, p));
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

/// Net worth dalam IDR: akun (aktif) + portofolio, dikonversi dengan kurs terakhir.
final netWorthProvider = Provider<AsyncValue<NetWorth>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final balances = ref.watch(accountBalancesProvider);
  final holdings = ref.watch(holdingsProvider);
  final fx = ref.watch(fxTableProvider);

  for (final value in <AsyncValue<Object?>>[accounts, balances, holdings, fx]) {
    if (value.hasError) {
      return AsyncValue.error(value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  final accountList = accounts.valueOrNull;
  final balanceMap = balances.valueOrNull;
  final holdingList = holdings.valueOrNull;
  final fxTable = fx.valueOrNull;
  if (accountList == null ||
      balanceMap == null ||
      holdingList == null ||
      fxTable == null) {
    return const AsyncValue.loading();
  }

  final cashByCurrency = <String, int>{};
  for (final a in accountList) {
    cashByCurrency[a.currency] = (cashByCurrency[a.currency] ?? 0) +
        (balanceMap[a.id] ?? a.openingBalanceMinor);
  }

  return AsyncValue.data(
    computeNetWorth(
      cashByCurrency: cashByCurrency,
      holdings: holdingList,
      fx: fxTable,
    ),
  );
});
