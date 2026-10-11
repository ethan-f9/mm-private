import 'package:decimal/decimal.dart';

import 'id_amount_parser.dart';
import 'money.dart';

/// Ubah teks input user menjadi minor unit untuk [currency].
///
/// - IDR: format Indonesia ("25k", "1,5jt", "Rp 25.000") via [IdAmountParser].
/// - Currency lain: angka biasa, titik atau koma sebagai desimal, tanpa
///   pemisah ribuan ("12.34", "12,34", "1200").
/// Return null kalau tidak valid.
int? parseAmountMinor(String input, String currency) {
  final text = input.trim();
  if (text.isEmpty) return null;

  if (currency == 'IDR') {
    return IdAmountParser.parse(text);
  }

  final value = Decimal.tryParse(text.replaceAll(',', '.'));
  if (value == null) return null;
  return Money.fromDecimal(value, currency).minor;
}
