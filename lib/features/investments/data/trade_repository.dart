import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/investments/domain/cost_basis_calculator.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:uuid/uuid.dart';

/// Validasi di sini, bukan di UI:
/// - jumlah dan harga > 0, fee >= 0
/// - akun pendanaan (opsional) harus bermata uang sama dengan aset
/// - jual tidak boleh melebihi unit yang dimiliki pada tanggal itu
///   (dihitung ulang dari semua trade, jadi trade mundur ikut divalidasi)
/// - menghapus trade tidak boleh membuat trade lain menjadi tidak sah
class TradeRepository {
  TradeRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();
  static const _calculator = CostBasisCalculator();

  Stream<List<Trade>> watchAll() {
    final query = _db.select(_db.trades)
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch();
  }

  Stream<List<Trade>> watchForAsset(String assetId) {
    final query = _db.select(_db.trades)
      ..where((t) => t.assetId.equals(assetId))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch();
  }

  Future<String> addTrade({
    required String assetId,
    required TradeSide side,
    required Decimal quantity,
    required Decimal price,
    required DateTime occurredAt,
    int feeMinor = 0,
    String? fundingAccountId,
  }) async {
    if (quantity <= Decimal.zero) {
      throw ArgumentError('Jumlah unit harus lebih dari 0');
    }
    if (price <= Decimal.zero) {
      throw ArgumentError('Harga harus lebih dari 0');
    }
    if (feeMinor < 0) {
      throw ArgumentError('Fee tidak boleh negatif');
    }

    final asset = await (_db.select(_db.assets)..where((a) => a.id.equals(assetId)))
        .getSingleOrNull();
    if (asset == null) {
      throw ArgumentError('Aset tidak ditemukan: $assetId');
    }

    if (fundingAccountId != null) {
      final account = await (_db.select(_db.accounts)
            ..where((a) => a.id.equals(fundingAccountId)))
          .getSingleOrNull();
      if (account == null) {
        throw ArgumentError('Akun tidak ditemukan: $fundingAccountId');
      }
      if (account.currency != asset.currency) {
        throw ArgumentError(
          'Akun pendanaan harus bermata uang ${asset.currency}, '
          'sama dengan aset',
        );
      }
    }

    final candidate = TradeInput(
      side: side,
      quantity: quantity,
      price: price,
      fee: Decimal.fromInt(feeMinor).shift(-_scale(asset.currency)),
      occurredAt: occurredAt,
    );
    final existing = await (_db.select(_db.trades)
          ..where((t) => t.assetId.equals(assetId)))
        .get();
    _assertValid([
      for (final t in existing) toTradeInput(t, asset.currency),
      candidate,
    ]);

    final id = _uuid.v4();
    await _db.into(_db.trades).insert(
          TradesCompanion.insert(
            id: id,
            assetId: assetId,
            fundingAccountId: Value(fundingAccountId),
            side: side,
            quantity: quantity,
            price: price,
            feeMinor: Value(feeMinor),
            occurredAt: occurredAt,
          ),
        );
    return id;
  }

  Future<void> deleteTrade(String id) async {
    final trade = await (_db.select(_db.trades)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (trade == null) return;

    final asset = await (_db.select(_db.assets)
          ..where((a) => a.id.equals(trade.assetId)))
        .getSingle();
    final remaining = await (_db.select(_db.trades)
          ..where((t) => t.assetId.equals(trade.assetId) & t.id.equals(id).not()))
        .get();

    try {
      _assertValid([for (final t in remaining) toTradeInput(t, asset.currency)]);
    } on ArgumentError {
      throw ArgumentError(
        'Tidak bisa dihapus: transaksi lain bergantung padanya '
        '(hapus penjualan yang lebih baru dulu).',
      );
    }
    await (_db.delete(_db.trades)..where((t) => t.id.equals(id))).go();
  }

  void _assertValid(List<TradeInput> trades) {
    try {
      _calculator.compute(trades);
    } on OversellException {
      throw ArgumentError('Jumlah jual melebihi unit yang dimiliki');
    }
  }

  static int _scale(String currency) =>
      (currency == 'IDR' || currency == 'JPY') ? 0 : 2;
}
