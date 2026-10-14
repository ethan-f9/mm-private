import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/investments/data/asset_repository.dart';
import 'package:personal_finance_manager/features/investments/data/fx_repository.dart';
import 'package:personal_finance_manager/features/investments/data/price_repository.dart';
import 'package:personal_finance_manager/features/investments/data/trade_repository.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth_history.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late TransactionRepository txs;
  late AssetRepository assets;
  late TradeRepository trades;
  late PriceRepository prices;
  late FxRepository fx;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    txs = TransactionRepository(db);
    assets = AssetRepository(db);
    trades = TradeRepository(db);
    prices = PriceRepository(db);
    fx = FxRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<NetWorthPoint>> history(DateTime today, {List<Account>? only}) async {
    return computeNetWorthHistory(
      today: today,
      accounts: only ?? await db.select(db.accounts).get(),
      transactions: await db.select(db.transactions).get(),
      transfers: await db.select(db.transfers).get(),
      trades: await db.select(db.trades).get(),
      assets: await db.select(db.assets).get(),
      prices: await db.select(db.priceSnapshots).get(),
      fxRates: await db.select(db.fxRates).get(),
    );
  }

  test('tanpa kejadian apa pun: riwayat kosong', () async {
    await accounts.create(
      name: 'Cash', type: AccountType.cash, currency: 'IDR', openingBalanceMinor: 1000,
    );
    expect(await history(DateTime(2026, 10, 10)), isEmpty);
  });

  test('kas harian: saldo awal + kejadian, hari tanpa kejadian meneruskan nilai',
      () async {
    final a = await accounts.create(
      name: 'Bank', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 1000000,
    );
    await txs.addTransaction(
      accountId: a.id, kind: TxKind.income, amountMinor: 500000,
      occurredAt: DateTime(2026, 10, 5, 12),
    );
    await txs.addTransaction(
      accountId: a.id, kind: TxKind.expense, amountMinor: 200000,
      occurredAt: DateTime(2026, 10, 7, 12),
    );

    final h = await history(DateTime(2026, 10, 10, 15));
    expect(h.length, 6); // 5..10 Okt
    expect(h.map((p) => p.date.day).toList(), [5, 6, 7, 8, 9, 10]);
    expect(
      h.map((p) => p.totalMinor).toList(),
      [1500000, 1500000, 1300000, 1300000, 1300000, 1300000],
    );
    expect(h.every((p) => p.cashMinor == p.totalMinor), isTrue);
    expect(h.every((p) => !p.estimated && p.complete), isTrue);
  });

  test('transfer antar akun tidak mengubah total, fee mengurangi', () async {
    final a = await accounts.create(
      name: 'A', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 1000000,
    );
    final b = await accounts.create(
      name: 'B', type: AccountType.bank, currency: 'IDR',
    );
    await txs.addTransfer(
      fromAccountId: a.id, toAccountId: b.id, fromAmountMinor: 400000,
      toAmountMinor: 400000, feeMinor: 2500, occurredAt: DateTime(2026, 10, 3, 9),
    );
    final h = await history(DateTime(2026, 10, 3));
    expect(h.single.totalMinor, 1000000 - 2500);
  });

  test('investasi: dinilai pada modal sebelum ada harga, lalu harga pasar, lalu jual',
      () async {
    final cash = await accounts.create(
      name: 'RDN', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 10000000,
    );
    final bbca = await assets.create(
      type: AssetType.stock, symbol: 'BBCA', name: 'BCA', currency: 'IDR',
    );
    await trades.addTrade(
      assetId: bbca.id, side: TradeSide.buy, quantity: d('10'), price: d('100000'),
      feeMinor: 1000, fundingAccountId: cash.id, occurredAt: DateTime(2026, 10, 2, 10),
    );
    await prices.saveManual(bbca.id, d('120000'), at: DateTime(2026, 10, 4, 12));
    await trades.addTrade(
      assetId: bbca.id, side: TradeSide.sell, quantity: d('4'), price: d('130000'),
      fundingAccountId: cash.id, occurredAt: DateTime(2026, 10, 6, 10),
    );

    final h = await history(DateTime(2026, 10, 8, 9));
    expect(h.map((p) => p.date.day).toList(), [2, 3, 4, 5, 6, 7, 8]);

    // 2-3 Okt: tanpa harga -> modal 1.001.000
    expect(h[0].cashMinor, 8999000);
    expect(h[0].investmentsMinor, 1001000);
    expect(h[0].totalMinor, 10000000);
    expect(h[0].estimated, isTrue);
    expect(h[1].investmentsMinor, 1001000);

    // 4-5 Okt: harga 120.000 x 10
    expect(h[2].investmentsMinor, 1200000);
    expect(h[2].totalMinor, 8999000 + 1200000);
    expect(h[2].estimated, isFalse);
    expect(h[3].investmentsMinor, 1200000);

    // 6 Okt: jual 4 unit (+520.000 kas), sisa 6 x 120.000
    expect(h[4].cashMinor, 8999000 + 520000);
    expect(h[4].investmentsMinor, 720000);
    expect(h[6].totalMinor, 8999000 + 520000 + 720000);
  });

  test('kurs: sebelum kurs pertama memakai kurs terdekat (estimasi), lalu mengikuti tanggal',
      () async {
    final wise = await accounts.create(
      name: 'Wise', type: AccountType.foreign, currency: 'USD', openingBalanceMinor: 10000,
    );
    await txs.addTransaction(
      accountId: wise.id, kind: TxKind.expense, amountMinor: 1000,
      occurredAt: DateTime(2026, 10, 3, 12),
    );
    await fx.saveQuotes([
      FxQuote(currency: 'USD', rate: d('16000'), date: DateTime(2026, 10, 5)),
      FxQuote(currency: 'USD', rate: d('16500'), date: DateTime(2026, 10, 8)),
    ]);

    final h = await history(DateTime(2026, 10, 9));
    expect(h.map((p) => p.date.day).toList(), [3, 4, 5, 6, 7, 8, 9]);
    // USD 90,00
    expect(h[0].totalMinor, 1440000); // 3 Okt: kurs terdekat 16.000
    expect(h[0].estimated, isTrue);
    expect(h[1].estimated, isTrue);
    expect(h[2].totalMinor, 1440000); // 5 Okt: kurs 16.000 resmi
    expect(h[2].estimated, isFalse);
    expect(h[5].totalMinor, 1485000); // 8 Okt: kurs 16.500
    expect(h[6].totalMinor, 1485000);
  });

  test('currency tanpa kurs sama sekali: titik ditandai tidak lengkap', () async {
    final wise = await accounts.create(
      name: 'Wise', type: AccountType.foreign, currency: 'USD', openingBalanceMinor: 10000,
    );
    await txs.addTransaction(
      accountId: wise.id, kind: TxKind.expense, amountMinor: 1000,
      occurredAt: DateTime(2026, 10, 3),
    );
    final h = await history(DateTime(2026, 10, 4));
    expect(h.every((p) => !p.complete), isTrue);
    expect(h.every((p) => p.totalMinor == 0), isTrue);
  });

  test('akun yang tidak disertakan (arsip) tidak ikut, kejadiannya diabaikan',
      () async {
    final keep = await accounts.create(
      name: 'Aktif', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 1000,
    );
    final archived = await accounts.create(
      name: 'Lama', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 9000,
    );
    await txs.addTransaction(
      accountId: keep.id, kind: TxKind.income, amountMinor: 100,
      occurredAt: DateTime(2026, 10, 2),
    );
    await txs.addTransaction(
      accountId: archived.id, kind: TxKind.income, amountMinor: 500,
      occurredAt: DateTime(2026, 10, 2),
    );
    final h = await history(DateTime(2026, 10, 2), only: [keep]);
    expect(h.single.totalMinor, 1100);
  });

  test('titik terakhir SAMA dengan net worth hari ini (hitung per sumber)', () async {
    final cash = await accounts.create(
      name: 'RDN', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 20000000,
    );
    final bank = await accounts.create(
      name: 'BCA', type: AccountType.bank, currency: 'IDR', openingBalanceMinor: 5000000,
    );
    final wise = await accounts.create(
      name: 'Wise', type: AccountType.foreign, currency: 'USD', openingBalanceMinor: 100000,
    );
    final wise2 = await accounts.create(
      name: 'Wise 2', type: AccountType.foreign, currency: 'USD', openingBalanceMinor: 3333,
    );

    final bbca = await assets.create(
      type: AssetType.stock, symbol: 'BBCA', name: 'BCA', currency: 'IDR',
    );
    final aapl = await assets.create(
      type: AssetType.stock, symbol: 'AAPL', name: 'Apple', currency: 'USD',
    );
    final btc = await assets.create(
      type: AssetType.crypto, symbol: 'BTC', name: 'Bitcoin', currency: 'IDR',
      externalId: 'bitcoin',
    );
    final gold = await assets.create(
      type: AssetType.gold, symbol: 'EMAS', name: 'Emas', currency: 'IDR',
    );

    await txs.addTransaction(
      accountId: bank.id, kind: TxKind.income, amountMinor: 9500000,
      occurredAt: DateTime(2026, 9, 25, 9),
    );
    await txs.addTransaction(
      accountId: bank.id, kind: TxKind.expense, amountMinor: 123456,
      occurredAt: DateTime(2026, 10, 1, 9),
    );
    await txs.addTransfer(
      fromAccountId: bank.id, toAccountId: wise.id, fromAmountMinor: 3300000,
      toAmountMinor: 20000, feeMinor: 25000, occurredAt: DateTime(2026, 9, 12, 9),
    );
    await trades.addTrade(
      assetId: bbca.id, side: TradeSide.buy, quantity: d('500'), price: d('9200'),
      feeMinor: 6900, fundingAccountId: cash.id, occurredAt: DateTime(2026, 9, 1, 10),
    );
    await trades.addTrade(
      assetId: bbca.id, side: TradeSide.sell, quantity: d('200'), price: d('10100'),
      feeMinor: 5050, fundingAccountId: cash.id, occurredAt: DateTime(2026, 10, 2, 10),
    );
    await trades.addTrade(
      assetId: aapl.id, side: TradeSide.buy, quantity: d('3'), price: d('190.5'),
      feeMinor: 100, fundingAccountId: wise.id, occurredAt: DateTime(2026, 9, 15, 10),
    );
    await trades.addTrade(
      assetId: btc.id, side: TradeSide.buy, quantity: d('0.005'),
      price: d('1050000000'), feeMinor: 15000, fundingAccountId: bank.id,
      occurredAt: DateTime(2026, 9, 20, 10),
    );
    await trades.addTrade(
      assetId: gold.id, side: TradeSide.buy, quantity: d('5'), price: d('1450000'),
      occurredAt: DateTime(2026, 9, 2, 10),
    ); // tanpa harga, tanpa akun
    await prices.saveManual(bbca.id, d('10050'), at: DateTime(2026, 10, 12, 9));
    await prices.saveManual(aapl.id, d('224.3'), at: DateTime(2026, 10, 10, 9));
    await prices.saveAuto(
      {btc.id: d('1185000000')}, source: 'coingecko', at: DateTime(2026, 10, 14, 8),
    );
    await fx.saveQuotes([
      FxQuote(currency: 'USD', rate: d('16350'), date: DateTime(2026, 10, 6)),
      FxQuote(currency: 'USD', rate: d('16480'), date: DateTime(2026, 10, 13)),
    ]);

    // Net worth "hari ini" lewat jalur yang dipakai layar Ringkasan.
    final balances = await accounts.balances();
    final accountList = await db.select(db.accounts).get();
    final cashByCurrency = <String, int>{};
    for (final a in accountList) {
      cashByCurrency[a.currency] = (cashByCurrency[a.currency] ?? 0) + balances[a.id]!;
    }
    final holdings = buildHoldings(
      await db.select(db.assets).get(),
      await db.select(db.trades).get(),
      await prices.watchLatest().first,
    );
    final nw = computeNetWorth(
      cashByCurrency: cashByCurrency,
      holdings: holdings,
      fx: await fx.latest(),
    );

    final h = await history(DateTime(2026, 10, 14, 18));
    expect(h.last.date, DateTime(2026, 10, 14));
    expect(h.last.cashMinor, nw.cashMinor);
    expect(h.last.investmentsMinor, nw.investmentsMinor);
    expect(h.last.totalMinor, nw.totalMinor);
    expect(wise2.id, isNotEmpty);
  });

  group('sliceHistory', () {
    final points = [
      for (var i = 1; i <= 10; i++)
        NetWorthPoint(
          date: DateTime(2026, 10, i),
          cashMinor: i * 100,
          investmentsMinor: 0,
          estimated: false,
          complete: true,
        ),
    ];

    test('0 = semua', () {
      expect(sliceHistory(points, 0, DateTime(2026, 10, 10)).length, 10);
    });

    test('N hari terakhir termasuk hari batas', () {
      final s = sliceHistory(points, 3, DateTime(2026, 10, 10));
      expect(s.map((p) => p.date.day).toList(), [7, 8, 9, 10]);
    });

    test('rentang lebih panjang dari data mengembalikan semuanya', () {
      expect(sliceHistory(points, 365, DateTime(2026, 10, 10)).length, 10);
    });
  });
}
