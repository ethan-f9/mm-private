import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

/// Simpan Decimal sebagai TEXT supaya presisi crypto (8+ desimal) dan emas
/// (gram) tidak hilang. Agregasi kolom ini dikerjakan di Dart, bukan SQL.
class DecimalConverter extends TypeConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);

  @override
  String toSql(Decimal value) => value.toString();
}
