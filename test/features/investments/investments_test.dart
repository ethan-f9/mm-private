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
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_cash.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late AssetRepository assets;
  late TradeRepository trades;
  late PriceRepository prices;
  late FxRepository fx;
  late Account cash;
  late Account wise;
  late Asset bbca;

  final oct10 = DateTime(2026, 10, 10, 10);
  final oct11 = DateTime(2026, 10, 11, 10);
  final oct12 = DateTime(2026, 10, 12, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    assets = AssetRepository(db);
    trades = TradeRepository(db);
    prices = PriceRepository(db);
    fx = FxRepository(db);

    cash = await accounts.create(
      name: 'RDN',
      type: AccountType.bank,
      currency: 'IDR',
      openingBalanceMinor: 10000000,
    );
    wise = await accounts.create(
      name: 'Wise',
      type: AccountType.foreign,
      currency: 'USD',
      openingBalanceMinor: 100000, // USD 1000.00
    );
    bbca = await assets.create(
      type: AssetType.stock,
      symbol: 'bbca',
      name: 'Bank Central Asia',
      currency: 'IDR',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<Holding>> holdings() async => buildHoldings(
        await assets.watchAll().first,
        await trades.watchAll().first,
        await prices.watchLatest().first,
      );

  group('aset', () {
    test('kode dijadikan huruf besar', () {
      expect(bbca.symbol, 'BBCA');
      expect(bbca.priceSource, PriceSource.manual);
    });

    test('crypto dengan ID CoinGecko: harga otomatis', () async {
      final btc = await assets.create(
        type: AssetType.crypto,
        symbol: 'BTC',
        name: 'Bitcoin',
        currency: 'IDR',
        externalId: ' Bitcoin ',
      );
      expect(btc.priceSource, PriceSource.auto);
      expect(btc.externalId, 'bitcoin');
    });

    test('ID CoinGecko diabaikan untuk jenis selain crypto', () async {
      final fund = await assets.create(
        type: AssetType.fund,
        symbol: 'RDPT',
        name: 'Reksadana',
        currency: 'IDR',
        externalId: 'bitcoin',
      );
      expect(fund.priceSource, PriceSource.manual);
      expect(fund.externalId, isNull);
    });

    test('kode atau nama kosong ditolak', () {
      expect(
        assets.create(type: AssetType.stock, symbol: ' ', name: 'x', currency: 'IDR'),
        throwsArgumentError,
      );
      expect(
        assets.create(type: AssetType.stock, symbol: 'X', name: ' ', currency: 'IDR'),
        throwsArgumentError,
      );
    });

    test('aset dengan transaksi tidak bisa dihapus; tanpa transaksi bisa', () async {
      await trades.addTrade(
        assetId: bbca.id,
        side: TradeSide.buy,
        quantity: d('10'),
        price: d('9000'),
        occurredAt: oct10,
      );
      await expectLater(assets.delete(bbca.id), throwsArgumentError);

      final empty = await assets.create(
        type: AssetType.gold,
        symbol: 'EMAS',
        name: 'Emas',
        currency: 'IDR',
      );
      await assets.delete(empty.id);
      expect((await assets.watchAll().first).map((a) => a.id), isNot(contains(empty.id)));
    });
  });

  group('validasi trade', () {
    Future<String> buy({String? funding}) => trades.addTrade(
          assetId: bbca.id,
          side: TradeSide.buy,
          quantity: d('10'),
          price: d('100000'),
          feeMinor: 1000,
          fundingAccountId: funding,
          occurredAt: oct10,
        );

    test('jumlah, harga, dan fee divalidasi', () {
      expect(
        trades.addTrade(
          assetId: bbca.id, side: TradeSide.buy, quantity: d('0'),
          price: d('1'), occurredAt: oct10,
        ),
        throwsArgumentError,
      );
      expect(
        trades.addTrade(
          assetId: bbca.id, side: TradeSide.buy, quantity: d('1'),
          price: d('0'), occurredAt: oct10,
        ),
        throwsArgumentError,
      );
      expect(
        trades.addTrade(
          assetId: bbca.id, side: TradeSide.buy, quantity: d('1'),
          price: d('1'), feeMinor: -1, occurredAt: oct10,
        ),
        throwsArgumentError,
      );
    });

    test('aset tidak ada ditolak', () {
      expect(
        trades.addTrade(
          assetId: 'tidak-ada', side: TradeSide.buy, quantity: d('1'),
          price: d('1'), occurredAt: oct10,
        ),
        throwsArgumentError,
      );
    });

    test('akun pendanaan harus bermata uang sama dengan aset', () {
      expect(buy(funding: wise.id), throwsArgumentError);
    });

    test('jual melebihi unit ditolak', () async {
      await buy();
      expect(
        trades.addTrade(
          assetId: bbca.id, side: TradeSide.sell, quantity: d('11'),
          price: d('1'), occurredAt: oct11,
        ),
        throwsArgumentError,
      );
    });

    test('jual yang tanggalnya lebih awal dari pembelian ditolak', () async {
      await buy(); // 10 Okt
      expect(
        trades.addTrade(
          assetId: bbca.id, side: TradeSide.sell, quantity: d('1'),
          price: d('1'), occurredAt: DateTime(2026, 10, 5),
        ),
        throwsArgumentError,
      );
    });

    test('hapus pembelian yang masih dibutuhkan penjualan ditolak', () async {
      final buyId = await buy();
      final sellId = await trades.addTrade(
        assetId: bbca.id, side: TradeSide.sell, quantity: d('4'),
        price: d('120000'), occurredAt: oct11,
      );
      await expectLater(trades.deleteTrade(buyId), throwsArgumentError);
      await trades.deleteTrade(sellId); // penjualan boleh
      await trades.deleteTrade(buyId); // sekarang boleh
      expect(await trades.watchAll().first, isEmpty);
    });
  });

  group('posisi dan average cost', () {
    test('beli, jual sebagian, harga pasar', () async {
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('10'),
        price: d('100000'), feeMinor: 1000, occurredAt: oct10,
      );
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.sell, quantity: d('4'),
        price: d('120000'), occurredAt: oct11,
      );
      await prices.saveManual(bbca.id, d('130000'), at: oct12);

      final h = (await holdings()).single;
      // modal 1.001.000; jual 4 unit: modal keluar 400.400, hasil 480.000
      expect(h.position.units, d('6'));
      expect(h.position.totalCost, d('600600'));
      expect(h.position.realizedGain, d('79600'));
      expect(h.marketValue, d('780000'));
      expect(h.unrealizedGain, d('179400'));
      expect(h.isHeld, isTrue);
    });

    test('tanpa harga: nilai pasar null', () async {
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('1'),
        price: d('100'), occurredAt: oct10,
      );
      final h = (await holdings()).single;
      expect(h.marketValue, isNull);
      expect(h.unrealizedGain, isNull);
    });

    test('terjual semua: tidak dianggap dimiliki', () async {
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('2'),
        price: d('100'), occurredAt: oct10,
      );
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.sell, quantity: d('2'),
        price: d('110'), occurredAt: oct11,
      );
      expect((await holdings()).single.isHeld, isFalse);
    });
  });

  group('dampak kas ke saldo akun', () {
    test('rumus beli, jual, dividen', () {
      expect(
        tradeCashDeltaMinor(
          side: TradeSide.buy, quantity: d('10'), price: d('100000'),
          feeMinor: 1000, currency: 'IDR',
        ),
        -1001000,
      );
      expect(
        tradeCashDeltaMinor(
          side: TradeSide.sell, quantity: d('4'), price: d('120000'),
          feeMinor: 500, currency: 'IDR',
        ),
        479500,
      );
      expect(
        tradeCashDeltaMinor(
          side: TradeSide.dividend, quantity: d('6'), price: d('2000'),
          feeMinor: 0, currency: 'IDR',
        ),
        12000,
      );
    });

    test('saldo akun pendanaan ikut berubah; tanpa akun tidak', () async {
      final buyId = await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('10'),
        price: d('100000'), feeMinor: 1000, fundingAccountId: cash.id,
        occurredAt: oct10,
      );
      expect((await accounts.balances())[cash.id], 10000000 - 1001000);

      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.sell, quantity: d('4'),
        price: d('120000'), feeMinor: 500, fundingAccountId: cash.id,
        occurredAt: oct11,
      );
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.dividend, quantity: d('6'),
        price: d('2000'), fundingAccountId: cash.id, occurredAt: oct12,
      );
      expect((await accounts.balances())[cash.id], 9490500);

      // trade tanpa akun pendanaan tidak mengubah saldo apa pun
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('1'),
        price: d('100000'), occurredAt: oct12,
      );
      expect((await accounts.balances())[cash.id], 9490500);
      expect(buyId, isNotEmpty);
    });

    test('menghapus trade mengembalikan saldo', () async {
      final id = await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('1'),
        price: d('100000'), fundingAccountId: cash.id, occurredAt: oct10,
      );
      expect((await accounts.balances())[cash.id], 9900000);
      await trades.deleteTrade(id);
      expect((await accounts.balances())[cash.id], 10000000);
    });
  });

  group('harga', () {
    test('harga terbaru menang; harga nol ditolak', () async {
      await prices.saveManual(bbca.id, d('100'), at: oct10);
      await prices.saveManual(bbca.id, d('120'), at: oct12);
      await prices.saveManual(bbca.id, d('110'), at: oct11);
      final latest = (await prices.watchLatest().first)[bbca.id]!;
      expect(latest.price, d('120'));
      expect(latest.source, 'manual');
      expect(prices.saveManual(bbca.id, d('0')), throwsArgumentError);
    });

    test('harga otomatis tersimpan dengan sumbernya', () async {
      await prices.saveAuto({bbca.id: d('999')}, source: 'coingecko', at: oct12);
      final latest = (await prices.watchLatest().first)[bbca.id]!;
      expect(latest.price, d('999'));
      expect(latest.source, 'coingecko');
    });
  });

  group('kurs', () {
    test('simpan dan baca kurs terbaru per currency', () async {
      await fx.saveQuotes([
        FxQuote(currency: 'USD', rate: d('16400'), date: DateTime(2026, 10, 8)),
        FxQuote(currency: 'USD', rate: d('16500'), date: DateTime(2026, 10, 9)),
        FxQuote(currency: 'EUR', rate: d('19000'), date: DateTime(2026, 10, 9)),
      ]);
      final table = await fx.latest();
      expect(table.rateFor('USD'), d('16500'));
      expect(table.rateFor('EUR'), d('19000'));
      expect(table.rateFor('IDR'), Decimal.one);
      expect(table.rateFor('JPY'), isNull);
      expect(table.asOf, DateTime(2026, 10, 9));
    });

    test('konversi ke IDR memakai skala currency', () {
      final table = FxTable({'USD': d('16500')});
      // USD 100,00 (10000 minor) -> Rp 1.650.000
      expect(table.toBaseMinor(10000, 'USD'), 1650000);
      expect(table.toBaseMinor(5000, 'IDR'), 5000);
      expect(table.toBaseMinor(100, 'EUR'), isNull);
    });
  });

  group('net worth', () {
    Future<List<Holding>> scenario() async {
      await trades.addTrade(
        assetId: bbca.id, side: TradeSide.buy, quantity: d('10'),
        price: d('100000'), feeMinor: 1000, occurredAt: oct10,
      );
      await prices.saveManual(bbca.id, d('130000'), at: oct12);

      final aapl = await assets.create(
        type: AssetType.stock, symbol: 'AAPL', name: 'Apple', currency: 'USD',
      );
      await trades.addTrade(
        assetId: aapl.id, side: TradeSide.buy, quantity: d('2'),
        price: d('150'), occurredAt: oct10,
      );
      await prices.saveManual(aapl.id, d('200'), at: oct12);

      final gold = await assets.create(
        type: AssetType.gold, symbol: 'EMAS', name: 'Emas', currency: 'IDR',
      );
      await trades.addTrade(
        assetId: gold.id, side: TradeSide.buy, quantity: d('5'),
        price: d('1000000'), occurredAt: oct10,
      ); // tanpa harga
      return holdings();
    }

    test('lengkap: kas + investasi dikonversi ke IDR', () async {
      final h = await scenario();
      final fxTable = FxTable({'USD': d('16500')});

      final nw = computeNetWorth(
        cashByCurrency: {'IDR': 8999000, 'USD': 100000},
        holdings: h,
        fx: fxTable,
      );
      // kas: 8.999.000 + USD 1000 x 16.500 = 25.499.000
      expect(nw.cashMinor, 25499000);
      // BBCA 1.300.000 + AAPL USD 400 x 16.500 (6.600.000) + emas dinilai modal 5.000.000
      expect(nw.investmentsMinor, 12900000);
      expect(nw.totalMinor, 38399000);
      // belum terealisasi hanya dari aset berharga: 299.000 + 1.650.000
      expect(nw.unrealizedMinor, 1949000);
      expect(nw.unpricedCount, 1);
      expect(nw.isComplete, isTrue);
    });

    test('kurs belum ada: dilaporkan, tidak dianggap nol diam-diam', () async {
      final h = await scenario();
      final nw = computeNetWorth(
        cashByCurrency: {'IDR': 8999000, 'USD': 100000},
        holdings: h,
        fx: FxTable.empty,
      );
      expect(nw.isComplete, isFalse);
      expect(nw.missingFx, {'USD'});
      expect(nw.cashMinor, 8999000);
      expect(nw.investmentsMinor, 1300000 + 5000000);
    });
  });
}
