import 'package:decimal/decimal.dart';

import 'trade_side.dart';

/// Satu trade mentah. Semua nilai dalam currency aset (bukan minor unit).
///
/// - buy: biaya = quantity * price + fee
/// - sell: hasil = quantity * price - fee
/// - dividend: pendapatan = quantity * price - fee, di mana `quantity` = jumlah
///   unit yang dipegang dan `price` = dividen per unit. Tidak mengubah posisi.
class TradeInput {
  const TradeInput({
    required this.side,
    required this.quantity,
    required this.price,
    required this.fee,
    required this.occurredAt,
  });

  final TradeSide side;
  final Decimal quantity;
  final Decimal price;
  final Decimal fee;
  final DateTime occurredAt;
}

class OversellException implements Exception {
  OversellException(this.requested, this.available);

  final Decimal requested;
  final Decimal available;

  @override
  String toString() =>
      'OversellException: jual $requested, tersedia $available';
}

class PositionSummary {
  const PositionSummary({
    required this.units,
    required this.totalCost,
    required this.realizedGain,
    required this.dividendIncome,
  });

  /// Unit yang masih dipegang.
  final Decimal units;

  /// Total biaya perolehan posisi yang masih dipegang (termasuk fee beli).
  final Decimal totalCost;

  /// Laba/rugi dari penjualan, metode average cost, sudah dikurangi fee jual.
  final Decimal realizedGain;

  final Decimal dividendIncome;

  Decimal get averageCost => units == Decimal.zero
      ? Decimal.zero
      : (totalCost / units).toDecimal(scaleOnInfinitePrecision: 10);

  Decimal unrealizedGain(Decimal marketPrice) => units * marketPrice - totalCost;
}

/// Metode average cost. Satu-satunya sumber kebenaran untuk posisi:
/// hasil ini tidak disimpan di DB, selalu dihitung ulang dari `trades`.
class CostBasisCalculator {
  const CostBasisCalculator();

  PositionSummary compute(Iterable<TradeInput> trades) {
    final ordered = trades.toList().asMap().entries.toList()
      ..sort((a, b) {
        final byDate = a.value.occurredAt.compareTo(b.value.occurredAt);
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });

    var units = Decimal.zero;
    var totalCost = Decimal.zero;
    var realized = Decimal.zero;
    var dividends = Decimal.zero;

    for (final entry in ordered) {
      final t = entry.value;
      switch (t.side) {
        case TradeSide.buy:
          totalCost += t.quantity * t.price + t.fee;
          units += t.quantity;
        case TradeSide.sell:
          if (t.quantity > units) {
            throw OversellException(t.quantity, units);
          }
          final costRemoved = (totalCost * t.quantity / units)
              .toDecimal(scaleOnInfinitePrecision: 10);
          final proceeds = t.quantity * t.price - t.fee;
          realized += proceeds - costRemoved;
          totalCost -= costRemoved;
          units -= t.quantity;
          if (units == Decimal.zero) totalCost = Decimal.zero;
        case TradeSide.dividend:
          dividends += t.quantity * t.price - t.fee;
      }
    }

    return PositionSummary(
      units: units,
      totalCost: totalCost,
      realizedGain: realized,
      dividendIncome: dividends,
    );
  }
}
