import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_filter.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';

/// Bulan yang sedang dilihat (selalu tanggal 1, jam 00:00).
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Filter jenis, pencarian, dan rentang tanggal di layar Transaksi.
final ledgerFilterProvider =
    StateProvider<LedgerFilter>((ref) => const LedgerFilter());

/// Semua akun termasuk yang diarsipkan, untuk menampilkan nama di riwayat lama.
final allAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(includeArchived: true),
);

final _rangeTransactionsProvider =
    StreamProvider.family<List<TransactionRow>, LedgerRange>(
  (ref, range) => ref
      .watch(transactionRepositoryProvider)
      .watchBetween(range.from, range.to),
);

final _rangeTransfersProvider =
    StreamProvider.family<List<Transfer>, LedgerRange>(
  (ref, range) => ref
      .watch(transactionRepositoryProvider)
      .watchTransfersBetween(range.from, range.to),
);

/// Transaksi + transfer dalam satu rentang, digabung dan diurutkan terbaru dulu.
final rangeLedgerProvider =
    Provider.family<AsyncValue<List<LedgerItem>>, LedgerRange>((ref, range) {
  final tx = ref.watch(_rangeTransactionsProvider(range));
  final tr = ref.watch(_rangeTransfersProvider(range));

  if (tx.hasError) {
    return AsyncValue.error(tx.error!, tx.stackTrace ?? StackTrace.current);
  }
  if (tr.hasError) {
    return AsyncValue.error(tr.error!, tr.stackTrace ?? StackTrace.current);
  }

  final txs = tx.valueOrNull;
  final trs = tr.valueOrNull;
  if (txs == null || trs == null) return const AsyncValue.loading();

  final items = <LedgerItem>[
    for (final t in txs) TransactionItem(t),
    for (final t in trs) TransferItem(t),
  ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  return AsyncValue.data(items);
});

/// Satu bulan penuh. Dipakai Ringkasan.
final ledgerProvider =
    Provider.family<AsyncValue<List<LedgerItem>>, DateTime>(
  (ref, month) => ref.watch(rangeLedgerProvider(LedgerRange.month(month))),
);
