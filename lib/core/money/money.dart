import 'package:decimal/decimal.dart';

import 'currency_meta.dart';

/// Nominal uang sebagai integer minor unit + kode currency.
///
/// Jangan pernah pakai `double` untuk uang. Operasi lintas currency
/// ditolak; konversi harus lewat FX service secara eksplisit.
class Money {
  const Money(this.minor, this.currency);

  factory Money.zero(String currency) => Money(0, currency);

  /// Bulatkan [amount] ke minor unit currency (half away from zero).
  factory Money.fromDecimal(Decimal amount, String currency) {
    final scale = CurrencyMeta.of(currency).scale;
    final minor = amount.shift(scale).round().toBigInt().toInt();
    return Money(minor, currency);
  }

  final int minor;
  final String currency;

  Decimal toDecimal() {
    final scale = CurrencyMeta.of(currency).scale;
    return Decimal.fromInt(minor).shift(-scale);
  }

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Currency berbeda: $currency vs ${other.currency}. Konversi dulu lewat FX.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency ${toDecimal()}';
}
