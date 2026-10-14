import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_finance_manager/features/market/data/market_clients.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  final now = DateTime(2026, 10, 12, 8);

  group('parseFrankfurterRate', () {
    test('objek tunggal', () {
      final q = parseFrankfurterRate(
        '{"date":"2026-10-09","base":"USD","quote":"IDR","rate":16512.5}',
        'USD',
        now: now,
      );
      expect(q.currency, 'USD');
      expect(q.rate, d('16512.5'));
      expect(q.date, DateTime(2026, 10, 9));
    });

    test('array baris: ambil yang quote-nya IDR', () {
      final q = parseFrankfurterRate(
        '[{"date":"2026-10-09","base":"USD","quote":"EUR","rate":0.86},'
        '{"date":"2026-10-09","base":"USD","quote":"IDR","rate":16500}]',
        'USD',
        now: now,
      );
      expect(q.rate, d('16500'));
    });

    test('tanggal hilang: pakai waktu sekarang', () {
      final q = parseFrankfurterRate('{"rate":110.3}', 'JPY', now: now);
      expect(q.date, now);
    });

    test('respons rusak ditolak', () {
      for (final body in [
        'bukan json',
        '{"date":"2026-10-09"}',
        '{"rate":0}',
        '{"rate":-3}',
        '[]',
      ]) {
        expect(
          () => parseFrankfurterRate(body, 'USD', now: now),
          throwsA(isA<MarketDataException>()),
          reason: body,
        );
      }
    });
  });

  group('parseCoinGeckoPrices', () {
    test('harga per koin; koin tidak dikenal tidak muncul', () {
      final prices = parseCoinGeckoPrices(
        '{"bitcoin":{"idr":1500000000.5},"ethereum":{"idr":45000000}}',
        'IDR',
      );
      expect(prices['bitcoin'], d('1500000000.5'));
      expect(prices['ethereum'], d('45000000'));
      expect(prices.containsKey('fake'), isFalse);
    });

    test('harga sangat kecil tidak memakai notasi eksponen', () {
      final prices = parseCoinGeckoPrices('{"shib":{"usd":0.00001234}}', 'USD');
      expect(prices['shib'], d('0.00001234'));
    });

    test('objek kosong menghasilkan peta kosong', () {
      expect(parseCoinGeckoPrices('{}', 'IDR'), isEmpty);
    });

    test('mata uang tidak ada di respons diabaikan', () {
      expect(parseCoinGeckoPrices('{"bitcoin":{"usd":100}}', 'IDR'), isEmpty);
    });

    test('bukan objek ditolak', () {
      expect(
        () => parseCoinGeckoPrices('[1,2]', 'IDR'),
        throwsA(isA<MarketDataException>()),
      );
      expect(
        () => parseCoinGeckoPrices('x', 'IDR'),
        throwsA(isA<MarketDataException>()),
      );
    });
  });

  group('klien HTTP', () {
    test('Frankfurter memanggil /v2/rate/USD/IDR', () async {
      late Uri requested;
      final client = FrankfurterClient(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"date":"2026-10-09","base":"USD","quote":"IDR","rate":16500}',
            200,
          );
        }),
      );
      final q = await client.fetchToBase('USD', now: now);
      expect(requested.host, 'api.frankfurter.dev');
      expect(requested.path, '/v2/rate/USD/IDR');
      expect(q.rate, d('16500'));
    });

    test('Frankfurter: HTTP error menjadi MarketDataException', () async {
      final client = FrankfurterClient(
        httpClient: MockClient((_) async => http.Response('oops', 500)),
      );
      await expectLater(
        client.fetchToBase('USD', now: now),
        throwsA(isA<MarketDataException>()),
      );
    });

    test('CoinGecko: satu panggilan untuk semua koin, minta mata uang kecil',
        () async {
      late Uri requested;
      final client = CoinGeckoClient(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response('{"bitcoin":{"idr":1500000000}}', 200);
        }),
      );
      final prices = await client.fetchPrices({'bitcoin', 'ethereum'}, 'IDR');
      expect(requested.host, 'api.coingecko.com');
      expect(requested.path, '/api/v3/simple/price');
      expect(requested.queryParameters['vs_currencies'], 'idr');
      expect(requested.queryParameters['ids']!.split(',').toSet(), {'bitcoin', 'ethereum'});
      expect(prices['bitcoin'], d('1500000000'));
    });

    test('CoinGecko: 429 diberi pesan yang jelas', () async {
      final client = CoinGeckoClient(
        httpClient: MockClient((_) async => http.Response('', 429)),
      );
      await expectLater(
        client.fetchPrices({'bitcoin'}, 'IDR'),
        throwsA(
          isA<MarketDataException>().having((e) => e.message, 'pesan', contains('429')),
        ),
      );
    });

    test('CoinGecko: tanpa koin tidak memanggil jaringan', () async {
      var called = false;
      final client = CoinGeckoClient(
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(await client.fetchPrices({}, 'IDR'), isEmpty);
      expect(called, isFalse);
    });
  });
}
