import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/investments/data/asset_repository.dart';
import 'package:personal_finance_manager/features/investments/data/fx_repository.dart';
import 'package:personal_finance_manager/features/investments/data/price_repository.dart';
import 'package:personal_finance_manager/features/market/data/market_clients.dart';
import 'package:personal_finance_manager/features/market/data/market_refresh_service.dart';
import 'package:personal_finance_manager/features/market/data/market_settings.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late DateTime now;
  late bool fxFails;
  late int fxCalls;
  late int cryptoCalls;
  late MarketRefreshService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
    now = DateTime(2026, 10, 12, 9);
    fxFails = false;
    fxCalls = 0;
    cryptoCalls = 0;

    final accounts = AccountRepository(db);
    await accounts.create(name: 'Cash', type: AccountType.cash, currency: 'IDR');
    await accounts.create(name: 'Wise', type: AccountType.foreign, currency: 'USD');

    final assets = AssetRepository(db);
    await assets.create(
      type: AssetType.crypto, symbol: 'BTC', name: 'Bitcoin',
      currency: 'IDR', externalId: 'bitcoin',
    );
    await assets.create(
      type: AssetType.crypto, symbol: 'FAKE', name: 'Koin palsu',
      currency: 'IDR', externalId: 'fake-coin',
    );
    await assets.create(
      type: AssetType.stock, symbol: 'BBCA', name: 'BCA', currency: 'IDR',
    );

    service = MarketRefreshService(
      db: db,
      fx: FrankfurterClient(
        httpClient: MockClient((request) async {
          fxCalls++;
          if (fxFails) return http.Response('error', 500);
          return http.Response(
            '{"date":"2026-10-09","base":"USD","quote":"IDR","rate":16500}',
            200,
          );
        }),
      ),
      crypto: CoinGeckoClient(
        httpClient: MockClient((request) async {
          cryptoCalls++;
          return http.Response('{"bitcoin":{"idr":1500000000}}', 200);
        }),
      ),
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('refresh: kurs USD dan harga BTC tersimpan; ID tidak dikenal dilaporkan',
      () async {
    final result = await service.refresh();

    expect(result.fxUpdated, 1); // hanya USD; IDR tidak perlu
    expect(result.pricesUpdated, 1); // hanya BTC
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('fake-coin'));

    final fx = await FxRepository(db).latest();
    expect(fx.rateFor('USD'), Decimal.parse('16500'));

    final prices = await PriceRepository(db).watchLatest().first;
    final assets = await db.select(db.assets).get();
    final btc = assets.firstWhere((a) => a.symbol == 'BTC');
    expect(prices[btc.id]!.price, Decimal.parse('1500000000'));
    expect(prices[btc.id]!.source, 'coingecko');

    // saham manual tidak diambil otomatis
    final bbca = assets.firstWhere((a) => a.symbol == 'BBCA');
    expect(prices.containsKey(bbca.id), isFalse);

    expect(await settings.get(marketLastRefreshKey), now.toIso8601String());
    expect(await settings.get(marketErrorKey), contains('fake-coin'));
  });

  test('kurs gagal: harga crypto tetap diperbarui, error dicatat, tidak melempar',
      () async {
    fxFails = true;
    final result = await service.refresh();

    expect(result.fxUpdated, 0);
    expect(result.pricesUpdated, 1);
    expect(result.errors.any((e) => e.startsWith('Kurs USD')), isTrue);
    expect((await FxRepository(db).latest()).rateFor('USD'), isNull);
  });

  test('runIfStale: jalan pertama kali, lalu menunggu sampai data basi', () async {
    expect(await service.runIfStale(), isNotNull);
    expect(fxCalls, 1);

    // langsung lagi: terlalu dekat dengan percobaan sebelumnya
    expect(await service.runIfStale(), isNull);
    expect(fxCalls, 1);

    // 20 menit kemudian: jeda percobaan lewat, tapi data masih segar (< 6 jam)
    now = now.add(const Duration(minutes: 20));
    expect(await service.runIfStale(), isNull);

    // 7 jam kemudian: data basi
    now = now.add(const Duration(hours: 7));
    expect(await service.runIfStale(), isNotNull);
    expect(fxCalls, 2);
  });

  test('gagal total: percobaan ulang otomatis dibatasi 15 menit', () async {
    fxFails = true;
    await service.runIfStale();
    expect(fxCalls, 1);

    now = now.add(const Duration(minutes: 5));
    expect(await service.runIfStale(), isNull);
    expect(fxCalls, 1);

    now = now.add(const Duration(minutes: 11));
    await service.runIfStale();
    expect(fxCalls, 2);
  });

  test('crypto dipanggil satu kali walau ada banyak aset', () async {
    await service.refresh();
    expect(cryptoCalls, 1);
  });
}
