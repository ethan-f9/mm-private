import 'package:drift/native.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

final scenarioNow = DateTime(2026, 10, 12, 12);

AppDatabase newDb() => AppDatabase(NativeDatabase.memory());

NetWorth netWorthWithCash(int cash) => NetWorth(
      cashMinor: cash,
      investmentsMinor: 0,
      unrealizedMinor: 0,
      unpricedCount: 0,
      missingFx: const {},
    );

/// Skenario: pencatatan sejak 20 Jun 2026, "sekarang" 12 Okt 2026.
///  Jul  pemasukan 8jt, pengeluaran 4jt
///  Agu  pemasukan 8jt, pengeluaran 5jt
///  Sep  pemasukan 8jt, pengeluaran 6jt (1jt makanan 1 Sep, 5jt tagihan 20 Sep)
///  Okt  makanan 1,5jt (5 Okt, catatan "rahasia-merchant")
/// Rata-rata pengeluaran 5jt, pemasukan 8jt, rasio tabungan 37,5%.
Future<AdvisorMetrics> scenarioMetrics(
  AppDatabase db, {
  Map<String, int>? targets,
  int cash = 15000000,
}) async {
  final accounts = AccountRepository(db);
  final txs = TransactionRepository(db);
  final categories = CategoryRepository(db);
  await categories.seedDefaultsIfEmpty();
  final wallet = await accounts.create(
    name: 'Cash',
    type: AccountType.cash,
    currency: 'IDR',
  );

  Future<void> expense(DateTime at, int amount, String category, {String? note}) =>
      txs.addTransaction(
        accountId: wallet.id,
        kind: TxKind.expense,
        amountMinor: amount,
        categoryId: category,
        note: note,
        occurredAt: at,
      );
  Future<void> income(DateTime at, int amount) => txs.addTransaction(
        accountId: wallet.id,
        kind: TxKind.income,
        amountMinor: amount,
        categoryId: 'default-income-gaji',
        occurredAt: at,
      );

  await expense(DateTime(2026, 6, 20), 100000, 'default-expense-makanan');
  await income(DateTime(2026, 7, 1), 8000000);
  await expense(DateTime(2026, 7, 10), 4000000, 'default-expense-makanan');
  await income(DateTime(2026, 8, 1), 8000000);
  await expense(DateTime(2026, 8, 10), 5000000, 'default-expense-tagihan');
  await income(DateTime(2026, 9, 1), 8000000);
  await expense(DateTime(2026, 9, 1), 1000000, 'default-expense-makanan');
  await expense(DateTime(2026, 9, 20), 5000000, 'default-expense-tagihan');
  await expense(
    DateTime(2026, 10, 5),
    1500000,
    'default-expense-makanan',
    note: 'rahasia-merchant',
  );

  final rows = await txs.watchBetween(DateTime(2000), DateTime(2100)).first;
  final names = {for (final c in await categories.watchAll().first) c.id: c.name};

  return computeAdvisorMetrics(
    now: scenarioNow,
    transactions: rows,
    categoryNames: names,
    netWorth: netWorthWithCash(cash),
    holdings: const [],
    fx: FxTable.empty,
    targetBps: targets,
  );
}
