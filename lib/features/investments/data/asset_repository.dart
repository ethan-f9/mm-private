import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:uuid/uuid.dart';

class AssetRepository {
  AssetRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Asset>> watchAll() {
    final query = _db.select(_db.assets)
      ..orderBy([(a) => OrderingTerm.asc(a.symbol)]);
    return query.watch();
  }

  /// [externalId] (ID CoinGecko) hanya bermakna untuk crypto; kalau diisi,
  /// harga diambil otomatis. Selain itu harga diisi manual.
  Future<Asset> create({
    required AssetType type,
    required String symbol,
    required String name,
    required String currency,
    String? externalId,
  }) async {
    CurrencyMeta.of(currency);
    final trimmedSymbol = symbol.trim().toUpperCase();
    final trimmedName = name.trim();
    if (trimmedSymbol.isEmpty) {
      throw ArgumentError('Kode aset tidak boleh kosong');
    }
    if (trimmedName.isEmpty) {
      throw ArgumentError('Nama aset tidak boleh kosong');
    }

    final cleanedExternal = externalId?.trim().toLowerCase();
    final useAuto =
        type == AssetType.crypto && cleanedExternal != null && cleanedExternal.isNotEmpty;

    final id = _uuid.v4();
    await _db.into(_db.assets).insert(
          AssetsCompanion.insert(
            id: id,
            type: type,
            symbol: trimmedSymbol,
            name: trimmedName,
            currency: currency,
            priceSource: useAuto ? PriceSource.auto : PriceSource.manual,
            externalId: Value(useAuto ? cleanedExternal : null),
          ),
        );
    return (_db.select(_db.assets)..where((a) => a.id.equals(id))).getSingle();
  }

  /// Hanya aset tanpa trade yang boleh dihapus.
  Future<void> delete(String id) async {
    final trades = await (_db.select(_db.trades)
          ..where((t) => t.assetId.equals(id))
          ..limit(1))
        .get();
    if (trades.isNotEmpty) {
      throw ArgumentError('Aset masih punya transaksi. Hapus transaksinya dulu.');
    }
    await _db.transaction(() async {
      await (_db.delete(_db.priceSnapshots)..where((p) => p.assetId.equals(id))).go();
      await (_db.delete(_db.assets)..where((a) => a.id.equals(id))).go();
    });
  }
}
