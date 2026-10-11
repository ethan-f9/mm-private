import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'currency_meta.dart';

/// Format untuk tampilan saja (double aman di sini). Penyimpanan dan
/// kalkulasi tetap memakai integer minor unit / Decimal.
String formatMinor(int minor, String currency) {
  final meta = CurrencyMeta.of(currency);
  final divisor = math.pow(10, meta.scale).toInt();
  final format = NumberFormat.currency(
    locale: 'id_ID',
    symbol: '${meta.symbol} ',
    decimalDigits: meta.scale,
  );
  return format.format(minor / divisor);
}
