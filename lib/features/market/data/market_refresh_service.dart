import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/features/investments/data/fx_repository.dart';
import 'package:personal_finance_manager/features/investments/data/price_repository.dart';
import 'package:personal_finance_manager/features/market/data/market_clients.dart';
import 'package:personal_finance_manager/features/market/data/market_settings.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

class MarketRefreshResult {
  const MarketRefreshResult({
    required this.fxUpdated,
    required this.pricesUpdated,
    required this.errors,
  });

  final int fxUpdated;
  final int pricesUpdated;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// Ambil kurs (Frankfurter) untuk currency asing yang dipakai akun/aset,
/// dan harga crypto otomatis (CoinGecko). Saham IDX, reksadana, dan emas
/// TIDAK diambil otomatis; harganya diisi manual.
///
/// Tidak pernah melempar: kegagalan per sumber dikumpulkan di `errors`, dan
/// data lama tetap dipakai (UI menampilkan umur datanya).
class MarketRefreshService {
  MarketRefreshService({
    required AppDatabase db,
    required FrankfurterClient fx,
    required CoinGeckoClient crypto,
    DateTime Function()? clock,
  })  : _db = db,
        _fx = fx,
        _crypto = crypto,
        _fxRepo = FxRepository(db),
        _priceRepo = PriceRepository(db),
        _settings = SettingsRepository(db),
        _clock = clock ?? DateTime.now;

  /// Data lebih tua dari ini dianggap perlu diperbarui saat app dibuka.
  static const maxAge = Duration(hours: 6);

  /// Jeda minimum antar percobaan otomatis (mis. saat offline).
  static const minRetryGap = Duration(minutes: 15);

  final AppDatabase _db;
  final FrankfurterClient _fx;
  final CoinGeckoClient _crypto;
  final FxRepository _fxRepo;
  final PriceRepository _priceRepo;
  final SettingsRepository _settings;
  final DateTime Function() _clock;

  bool _running = false;

  /// Dipanggil otomatis saat app dibuka/kembali. Null kalau belum perlu.
  Future<MarketRefreshResult?> runIfStale() async {
    final now = _clock();
    final lastRefresh = await _readTime(marketLastRefreshKey);
    final lastAttempt = await _readTime(marketLastAttemptKey);
    if (lastAttempt != null &&
        lastAttempt.isBefore(now) &&
        now.difference(lastAttempt) < minRetryGap) {
      return null;
    }
    if (lastRefresh != null &&
        lastRefresh.isBefore(now) &&
        now.difference(lastRefresh) < maxAge) {
      return null;
    }
    return refresh();
  }

  Future<MarketRefreshResult> refresh() async {
    if (_running) {
      return const MarketRefreshResult(fxUpdated: 0, pricesUpdated: 0, errors: []);
    }
    _running = true;

    final now = _clock();
    final errors = <String>[];
    var fxUpdated = 0;
    var pricesUpdated = 0;

    try {
      await _settings.set(marketLastAttemptKey, now.toIso8601String());

      final accounts = await _db.select(_db.accounts).get();
      final assets = await _db.select(_db.assets).get();

      final currencies = <String>{
        for (final a in accounts)
          if (!a.archived) a.currency,
        for (final a in assets) a.currency,
      }..remove(CurrencyMeta.baseCurrency);

      final quotes = <FxQuote>[];
      for (final currency in currencies) {
        try {
          quotes.add(await _fx.fetchToBase(currency, now: now));
        } catch (e) {
          errors.add('Kurs $currency: $e');
        }
      }
      if (quotes.isNotEmpty) {
        await _fxRepo.saveQuotes(quotes);
        fxUpdated = quotes.length;
      }

      final auto = assets.where(
        (a) => a.priceSource == PriceSource.auto && (a.externalId ?? '').isNotEmpty,
      );
      final byCurrency = <String, List<Asset>>{};
      for (final a in auto) {
        byCurrency.putIfAbsent(a.currency, () => []).add(a);
      }
      for (final entry in byCurrency.entries) {
        try {
          final ids = {for (final a in entry.value) a.externalId!};
          final prices = await _crypto.fetchPrices(ids, entry.key);
          final byAsset = <String, Decimal>{};
          for (final a in entry.value) {
            final price = prices[a.externalId!];
            if (price == null) {
              errors.add('Harga ${a.symbol}: ID "${a.externalId}" tidak dikenal');
            } else {
              byAsset[a.id] = price;
            }
          }
          if (byAsset.isNotEmpty) {
            await _priceRepo.saveAuto(byAsset, source: 'coingecko', at: now);
            pricesUpdated += byAsset.length;
          }
        } catch (e) {
          errors.add('Harga crypto (${entry.key}): $e');
        }
      }

      if (fxUpdated + pricesUpdated > 0) {
        await _settings.set(marketLastRefreshKey, now.toIso8601String());
      }
      await _settings.set(marketErrorKey, errors.join('\n'));
    } catch (e) {
      errors.add(e.toString());
    } finally {
      _running = false;
    }

    return MarketRefreshResult(
      fxUpdated: fxUpdated,
      pricesUpdated: pricesUpdated,
      errors: errors,
    );
  }

  Future<DateTime?> _readTime(String key) async {
    final raw = await _settings.get(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}

final marketRefreshServiceProvider = Provider<MarketRefreshService>(
  (ref) => MarketRefreshService(
    db: ref.watch(appDatabaseProvider),
    fx: FrankfurterClient(),
    crypto: CoinGeckoClient(),
  ),
);

/// Kapan terakhir data pasar berhasil diperbarui. Null = belum pernah.
final marketLastRefreshProvider = FutureProvider<DateTime?>((ref) async {
  final raw =
      await ref.watch(settingsRepositoryProvider).get(marketLastRefreshKey);
  return raw == null ? null : DateTime.tryParse(raw);
});
