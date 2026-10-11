import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';

/// Bulan yang sedang dilihat (selalu tanggal 1, jam 00:00).
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Semua akun termasuk yang diarsipkan, untuk menampilkan nama di riwayat lama.
final allAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(includeArchived: true),
);

DateTime _nextMonth(DateTime month) => DateTime(month.year, month.month + 1);

final _monthTransactionsProvider =
    StreamProvider.family<List<TransactionRow>, DateTime>(
  (ref, month) => ref
      .watch(transactionRepositoryProvider)
      .watchBetween(month, _nextMonth(month)),
);

final _monthTransfersProvider = StreamProvider.family<List<Transfer>, DateTime>(
  (ref, month) => ref
      .watch(transactionRepositoryProvider)
      .watchTransfersBetween(month, _nextMonth(month)),
);

/// Transaksi + transfer satu bulan, digabung dan diurutkan terbaru dulu.
final ledgerProvider =
    Provider.family<AsyncValue<List<LedgerItem>>, DateTime>((ref, month) {
  final tx = ref.watch(_monthTransactionsProvider(month));
  final tr = ref.watch(_monthTransfersProvider(month));

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
