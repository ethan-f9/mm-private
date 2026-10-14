import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/features/investments/data/fx_repository.dart';

class MarketDataException implements Exception {
  const MarketDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

Decimal _decimalFromJson(Object? value) {
  if (value is int) return Decimal.fromInt(value);
  if (value is double) return Decimal.parse(value.toStringAsFixed(12));
  if (value is String) {
    final parsed = Decimal.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const MarketDataException('Angka tidak valid dalam respons');
}

/// Kurs harian ECB lewat Frankfurter (gratis, tanpa API key).
/// Endpoint v2: GET /v2/rate/{dari}/{ke} -> {"date","base","quote","rate"}.
/// Kurs ini harian (bukan real-time).
class FrankfurterClient {
  FrankfurterClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<FxQuote> fetchToBase(String currency, {DateTime? now}) async {
    final uri = Uri.https(
      'api.frankfurter.dev',
      '/v2/rate/$currency/${CurrencyMeta.baseCurrency}',
    );
    final res = await _http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw MarketDataException('HTTP ${res.statusCode}');
    }
    return parseFrankfurterRate(
      utf8.decode(res.bodyBytes),
      currency,
      now: now ?? DateTime.now(),
    );
  }
}

/// Menerima objek tunggal, atau array baris (bentuk /v2/rates).
FxQuote parseFrankfurterRate(String body, String currency, {required DateTime now}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MarketDataException('Respons kurs bukan JSON');
  }

  Map<String, dynamic>? row;
  if (decoded is Map<String, dynamic>) {
    row = decoded;
  } else if (decoded is List) {
    for (final item in decoded) {
      if (item is Map<String, dynamic> &&
          item['base'] == currency &&
          item['quote'] == CurrencyMeta.baseCurrency) {
        row = item;
        break;
      }
    }
  }
  if (row == null || row['rate'] == null) {
    throw const MarketDataException('Kurs tidak ditemukan dalam respons');
  }

  final rate = _decimalFromJson(row['rate']);
  if (rate <= Decimal.zero) {
    throw const MarketDataException('Kurs tidak valid');
  }
  return FxQuote(
    currency: currency,
    rate: rate,
    date: DateTime.tryParse(row['date']?.toString() ?? '') ?? now,
  );
}

/// Harga crypto dari API publik CoinGecko tanpa key (dibatasi per IP).
/// GET /api/v3/simple/price?ids=a,b&vs_currencies=idr
/// -> {"bitcoin":{"idr":1.5e9}}. Satu panggilan untuk semua koin.
class CoinGeckoClient {
  CoinGeckoClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// coinId -> harga dalam [vsCurrency]. ID yang tidak dikenal tidak muncul.
  Future<Map<String, Decimal>> fetchPrices(
    Set<String> coinIds,
    String vsCurrency,
  ) async {
    if (coinIds.isEmpty) return {};
    final uri = Uri.https('api.coingecko.com', '/api/v3/simple/price', {
      'ids': coinIds.join(','),
      'vs_currencies': vsCurrency.toLowerCase(),
    });
    final res = await _http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 429) {
      throw const MarketDataException(
        'CoinGecko membatasi permintaan (HTTP 429). Coba lagi beberapa menit lagi.',
      );
    }
    if (res.statusCode != 200) {
      throw MarketDataException('HTTP ${res.statusCode}');
    }
    return parseCoinGeckoPrices(utf8.decode(res.bodyBytes), vsCurrency);
  }
}

Map<String, Decimal> parseCoinGeckoPrices(String body, String vsCurrency) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MarketDataException('Respons harga bukan JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const MarketDataException('Format respons harga tidak dikenal');
  }

  final key = vsCurrency.toLowerCase();
  final prices = <String, Decimal>{};
  decoded.forEach((coinId, value) {
    if (value is Map<String, dynamic> && value[key] != null) {
      final price = _decimalFromJson(value[key]);
      if (price > Decimal.zero) prices[coinId] = price;
    }
  });
  return prices;
}
