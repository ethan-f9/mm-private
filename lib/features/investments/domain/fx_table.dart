import 'package:decimal/decimal.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/money/money.dart';

/// Kurs terakhir ke mata uang dasar (IDR): 1 unit [currency] = rate IDR.
class FxTable {
  const FxTable(this.rates, {this.asOf});

  static const empty = FxTable({});

  final Map<String, Decimal> rates;

  /// Tanggal kurs terbaru (tanggal publikasi sumber).
  final DateTime? asOf;

  Decimal? rateFor(String currency) =>
      currency == CurrencyMeta.baseCurrency ? Decimal.one : rates[currency];

  /// Konversi nominal [amount] (dalam [currency]) ke minor unit IDR.
  /// Null kalau kurs belum tersedia.
  int? decimalToBaseMinor(Decimal amount, String currency) {
    final rate = rateFor(currency);
    if (rate == null) return null;
    return Money.fromDecimal(amount * rate, CurrencyMeta.baseCurrency).minor;
  }

  /// Sama seperti [decimalToBaseMinor] tapi dari minor unit.
  int? toBaseMinor(int minor, String currency) =>
      decimalToBaseMinor(Money(minor, currency).toDecimal(), currency);
}
