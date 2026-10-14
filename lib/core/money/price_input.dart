import 'package:decimal/decimal.dart';

import 'id_amount_parser.dart';

/// Jumlah unit aset (boleh pecahan, mis. 0,005 BTC). Titik atau koma sebagai
/// desimal, tanpa pemisah ribuan. Null kalau tidak valid atau tidak positif.
Decimal? parseQuantity(String input) {
  final value = Decimal.tryParse(input.trim().replaceAll(',', '.'));
  if (value == null || value <= Decimal.zero) return null;
  return value;
}

/// Harga per unit dalam [currency]. IDR memakai format Indonesia
/// ("9.500", "1,35jt"); currency lain angka biasa. Null kalau tidak valid
/// atau tidak positif.
Decimal? parsePrice(String input, String currency) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final Decimal? value;
  if (currency == 'IDR') {
    final rupiah = IdAmountParser.parse(text);
    value = rupiah == null ? null : Decimal.fromInt(rupiah);
  } else {
    value = Decimal.tryParse(text.replaceAll(',', '.'));
  }
  if (value == null || value <= Decimal.zero) return null;
  return value;
}
