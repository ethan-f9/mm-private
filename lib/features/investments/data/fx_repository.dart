import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';

/// Satu kurs: 1 unit [currency] = [rate] IDR pada [date].
class FxQuote {
  const FxQuote({required this.currency, required this.rate, required this.date});

  final String currency;
  final Decimal rate;
  final DateTime date;
}

class FxRepository {
  FxRepository(this._db);

  final AppDatabase _db;

  Future<void> saveQuotes(List<FxQuote> quotes) async {
    await _db.batch((b) {
      for (final q in quotes) {
        b.insert(
          _db.fxRates,
          FxRatesCompanion.insert(
            date: DateTime(q.date.year, q.date.month, q.date.day),
            base: q.currency,
            quote: CurrencyMeta.baseCurrency,
            rate: q.rate,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Stream<FxTable> watchLatest() {
    final query = _db.select(_db.fxRates)
      ..orderBy([(r) => OrderingTerm.desc(r.date)]);
    return query.watch().map(_toTable);
  }

  /// Semua riwayat kurs (untuk rekonstruksi grafik net worth).
  Stream<List<FxRate>> watchAllRows() => _db.select(_db.fxRates).watch();

  Future<FxTable> latest() async {
    final query = _db.select(_db.fxRates)
      ..orderBy([(r) => OrderingTerm.desc(r.date)]);
    return _toTable(await query.get());
  }

  FxTable _toTable(List<FxRate> rows) {
    final rates = <String, Decimal>{};
    DateTime? asOf;
    for (final r in rows) {
      if (r.quote != CurrencyMeta.baseCurrency) continue;
      if (rates.containsKey(r.base)) continue; // baris terbaru lebih dulu
      rates[r.base] = r.rate;
      if (asOf == null || r.date.isAfter(asOf)) asOf = r.date;
    }
    return FxTable(rates, asOf: asOf);
  }
}
