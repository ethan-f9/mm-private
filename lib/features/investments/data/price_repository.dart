import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';

class PriceRepository {
  PriceRepository(this._db);

  final AppDatabase _db;

  /// Harga yang diisi user sendiri.
  Future<void> saveManual(String assetId, Decimal price, {DateTime? at}) async {
    if (price <= Decimal.zero) {
      throw ArgumentError('Harga harus lebih dari 0');
    }
    await _db.into(_db.priceSnapshots).insert(
          PriceSnapshotsCompanion.insert(
            assetId: assetId,
            price: price,
            fetchedAt: at ?? DateTime.now(),
            source: 'manual',
          ),
        );
  }

  /// Harga dari penyedia otomatis: assetId -> harga.
  Future<void> saveAuto(
    Map<String, Decimal> pricesByAssetId, {
    required String source,
    required DateTime at,
  }) async {
    await _db.batch((b) {
      pricesByAssetId.forEach((assetId, price) {
        b.insert(
          _db.priceSnapshots,
          PriceSnapshotsCompanion.insert(
            assetId: assetId,
            price: price,
            fetchedAt: at,
            source: source,
          ),
        );
      });
    });
  }

  /// Semua riwayat harga (untuk rekonstruksi grafik net worth).
  Stream<List<PriceSnapshot>> watchAll() => _db.select(_db.priceSnapshots).watch();

  /// Harga terbaru per aset.
  Stream<Map<String, PriceSnapshot>> watchLatest() {
    final query = _db.select(_db.priceSnapshots)
      ..orderBy([
        (p) => OrderingTerm.desc(p.fetchedAt),
        (p) => OrderingTerm.desc(p.id),
      ]);
    return query.watch().map((rows) {
      final latest = <String, PriceSnapshot>{};
      for (final row in rows) {
        latest.putIfAbsent(row.assetId, () => row);
      }
      return latest;
    });
  }
}
