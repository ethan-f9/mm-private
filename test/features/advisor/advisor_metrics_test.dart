import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/advisor/domain/allocation_presets.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

import 'advisor_test_support.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = newDb();
  });

  tearDown(() async {
    await db.close();
  });

  test('rata-rata bulanan, rasio tabungan, dan runway dari 3 bulan penuh', () async {
    final m = await scenarioMetrics(db);

    expect(m.hasEnoughData, isTrue);
    expect(m.dataSpanDays, 114);
    expect(m.months.length, 3);
    expect(m.months.map((x) => x.month.month).toList(), [7, 8, 9]);
    expect(m.months.map((x) => x.expenseMinor).toList(), [4000000, 5000000, 6000000]);
    expect(m.months.every((x) => x.incomeMinor == 8000000), isTrue);

    expect(m.avgMonthlyExpenseMinor, 5000000);
    expect(m.avgMonthlyIncomeMinor, 8000000);
    expect(m.savingsRatePct, closeTo(37.5, 0.001));
    expect(m.runwayMonths, closeTo(3.0, 0.001));
    expect(m.cashMinor, 15000000);
  });

  test('tren kategori: 30 hari terakhir vs 30 hari sebelumnya', () async {
    final m = await scenarioMetrics(db);

    expect(m.categoryTrends.length, 2);
    final tagihan = m.categoryTrends[0];
    expect(tagihan.name, 'Tagihan');
    expect(tagihan.last30Minor, 5000000);
    expect(tagihan.prev30Minor, 0);
    expect(tagihan.changePct, isNull); // tidak ada pembanding

    final makanan = m.categoryTrends[1];
    expect(makanan.name, 'Makanan');
    expect(makanan.last30Minor, 1500000);
    expect(makanan.prev30Minor, 1000000);
    expect(makanan.changePct, closeTo(50, 0.001));
  });

  test('alokasi tanpa target: aktual ada, target dan selisih kosong', () async {
    final m = await scenarioMetrics(db);
    expect(m.hasTargets, isFalse);
    final cash = m.allocation.firstWhere((a) => a.classKey == 'cash');
    expect(cash.actualPct, closeTo(100, 0.001));
    expect(cash.targetPct, isNull);
    expect(cash.driftPts, isNull);
  });

  test('alokasi dengan target: selisih = aktual - target', () async {
    final moderat = allocationPresets.firstWhere((p) => p.name == 'Moderat');
    final m = await scenarioMetrics(db, targets: moderat.bps);
    expect(m.hasTargets, isTrue);
    final cash = m.allocation.firstWhere((a) => a.classKey == 'cash');
    expect(cash.targetPct, closeTo(15, 0.001));
    expect(cash.driftPts, closeTo(85, 0.001));
    final stock = m.allocation.firstWhere((a) => a.classKey == 'stock');
    expect(stock.actualPct, closeTo(0, 0.001));
    expect(stock.driftPts, closeTo(-35, 0.001));
  });

  test('runway 0 kalau kas tidak positif', () async {
    final m = await scenarioMetrics(db, cash: -500000);
    expect(m.runwayMonths, 0);
  });

  group('data belum cukup', () {
    test('kurang dari 60 hari', () async {
      final accounts = AccountRepository(db);
      final txs = TransactionRepository(db);
      await CategoryRepository(db).seedDefaultsIfEmpty();
      final a = await accounts.create(
        name: 'Cash', type: AccountType.cash, currency: 'IDR',
      );
      await txs.addTransaction(
        accountId: a.id, kind: TxKind.expense, amountMinor: 1000,
        occurredAt: DateTime(2026, 10, 2),
      );
      final rows = await txs.watchBetween(DateTime(2000), DateTime(2100)).first;

      final m = computeAdvisorMetrics(
        now: scenarioNow,
        transactions: rows,
        categoryNames: const {},
        netWorth: netWorthWithCash(0),
        holdings: const [],
        fx: FxTable.empty,
        targetBps: null,
      );
      expect(m.hasEnoughData, isFalse);
      expect(m.months, isEmpty);
      expect(m.avgMonthlyExpenseMinor, isNull);
      expect(m.runwayMonths, isNull);
    });

    test('tanpa transaksi sama sekali', () {
      final m = computeAdvisorMetrics(
        now: scenarioNow,
        transactions: const [],
        categoryNames: const {},
        netWorth: netWorthWithCash(0),
        holdings: const [],
        fx: FxTable.empty,
        targetBps: null,
      );
      expect(m.dataSpanDays, 0);
      expect(m.hasEnoughData, isFalse);
    });
  });

  test('bulan pertama yang tidak lengkap (mulai setelah tanggal 7) dilewati',
      () async {
    final accounts = AccountRepository(db);
    final txs = TransactionRepository(db);
    final a = await accounts.create(
      name: 'Cash', type: AccountType.cash, currency: 'IDR',
    );
    Future<void> expense(DateTime at, int amount) => txs.addTransaction(
          accountId: a.id, kind: TxKind.expense, amountMinor: amount, occurredAt: at,
        );
    await expense(DateTime(2026, 7, 20), 1000000); // Juli tidak lengkap
    await expense(DateTime(2026, 8, 10), 5000000);
    await expense(DateTime(2026, 9, 10), 7000000);
    final rows = await txs.watchBetween(DateTime(2000), DateTime(2100)).first;

    final m = computeAdvisorMetrics(
      now: scenarioNow,
      transactions: rows,
      categoryNames: const {},
      netWorth: netWorthWithCash(0),
      holdings: const [],
      fx: FxTable.empty,
      targetBps: null,
    );
    expect(m.months.map((x) => x.month.month).toList(), [8, 9]);
    expect(m.avgMonthlyExpenseMinor, 6000000);
    expect(m.hasEnoughData, isTrue);
  });

  test('transaksi valas tanpa kurs tidak dihitung dan dilaporkan', () async {
    final accounts = AccountRepository(db);
    final txs = TransactionRepository(db);
    final usd = await accounts.create(
      name: 'Wise', type: AccountType.foreign, currency: 'USD',
    );
    await txs.addTransaction(
      accountId: usd.id, kind: TxKind.expense, amountMinor: 5000,
      occurredAt: DateTime(2026, 9, 3),
    );
    final rows = await txs.watchBetween(DateTime(2000), DateTime(2100)).first;

    final m = computeAdvisorMetrics(
      now: scenarioNow,
      transactions: rows,
      categoryNames: const {},
      netWorth: netWorthWithCash(0),
      holdings: const [],
      fx: FxTable.empty,
      targetBps: null,
    );
    expect(m.missingFx, {'USD'});
    expect(m.months.single.expenseMinor, 0);
  });
}
