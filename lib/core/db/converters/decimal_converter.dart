import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

/// Simpan Decimal sebagai TEXT supaya presisi crypto (8+ desimal) dan emas
/// (gram) tidak hilang. Agregasi kolom ini dikerjakan di Dart, bukan SQL.
///
/// `JsonTypeConverter2` dibutuhkan supaya `toJson()/fromJson()` data class
/// Drift (dipakai backup) membawa Decimal sebagai string, bukan objek mentah.
class DecimalConverter extends TypeConverter<Decimal, String>
    with JsonTypeConverter2<Decimal, String, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);

  @override
  String toSql(Decimal value) => value.toString();

  @override
  Decimal fromJson(String json) => Decimal.parse(json);

  @override
  String toJson(Decimal value) => value.toString();
}
