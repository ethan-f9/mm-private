import 'package:decimal/decimal.dart';

/// Normalisasi token nominal gaya Indonesia menjadi rupiah bulat.
///
/// Dipakai di Dart, bukan oleh LLM: model cukup mengembalikan string mentah
/// ("25k", "1,5jt"), parser ini yang menentukan angkanya.
///
/// Aturan:
/// - Suffix: `k`, `rb`, `ribu` = x1.000; `jt`, `juta` = x1.000.000.
/// - Prefix `Rp` / `Rp.` boleh ada.
/// - Titik + koma sekaligus: separator terakhir adalah desimal.
/// - Hanya titik: pola ribuan (`1.500`, `1.500.000`) dianggap ribuan, selain itu desimal.
/// - Hanya koma: desimal (gaya Indonesia).
/// - Hasil dibulatkan ke rupiah terdekat. Return null kalau tidak valid.
class IdAmountParser {
  IdAmountParser._();

  static final _pattern =
      RegExp(r'^(?:rp\.?\s*)?(\d[\d.,]*)\s*(k|rb|ribu|jt|juta)?$');
  static final _thousandsDots = RegExp(r'^\d{1,3}(\.\d{3})+$');

  static const _multipliers = <String, int>{
    'k': 1000,
    'rb': 1000,
    'ribu': 1000,
    'jt': 1000000,
    'juta': 1000000,
  };

  static int? parse(String input) {
    final match = _pattern.firstMatch(input.trim().toLowerCase());
    if (match == null) return null;

    final normalized = _normalize(match.group(1)!);
    final value = Decimal.tryParse(normalized);
    if (value == null) return null;

    final suffix = match.group(2);
    final multiplier = suffix == null ? 1 : _multipliers[suffix]!;
    return (value * Decimal.fromInt(multiplier)).round().toBigInt().toInt();
  }

  static String _normalize(String raw) {
    final hasDot = raw.contains('.');
    final hasComma = raw.contains(',');

    if (hasDot && hasComma) {
      return raw.lastIndexOf(',') > raw.lastIndexOf('.')
          ? raw.replaceAll('.', '').replaceAll(',', '.')
          : raw.replaceAll(',', '');
    }
    if (hasDot) {
      return _thousandsDots.hasMatch(raw) ? raw.replaceAll('.', '') : raw;
    }
    if (hasComma) {
      return raw.replaceAll(',', '.');
    }
    return raw;
  }
}
