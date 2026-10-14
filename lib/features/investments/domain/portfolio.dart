import 'package:decimal/decimal.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/money/money.dart';

import 'cost_basis_calculator.dart';
import 'fx_table.dart';

/// Posisi satu aset: hasil average cost + harga terakhir (kalau ada).
class Holding {
  const Holding({
    required this.asset,
    required this.position,
    required this.latestPrice,
    required this.priceAt,
  });

  final Asset asset;
  final PositionSummary position;
  final Decimal? latestPrice;
  final DateTime? priceAt;

  bool get isHeld => position.units > Decimal.zero;

  /// Nilai pasar dalam currency aset. Null kalau harga belum pernah diisi.
  Decimal? get marketValue {
    final price = latestPrice;
    return price == null ? null : position.units * price;
  }

  Decimal? get unrealizedGain {
    final value = marketValue;
    return value == null ? null : value - position.totalCost;
  }

  /// Persen untung/rugi terhadap modal; null kalau tidak bisa dihitung.
  double? get unrealizedPercent {
    final gain = unrealizedGain;
    if (gain == null || position.totalCost <= Decimal.zero) return null;
    return gain.toDouble() / position.totalCost.toDouble() * 100;
  }
}

/// Konversi trade tersimpan ke input kalkulator. Fee tersimpan sebagai minor
/// unit; kalkulator memakai Decimal dalam currency aset.
TradeInput toTradeInput(Trade trade, String currency) => TradeInput(
      side: trade.side,
      quantity: trade.quantity,
      price: trade.price,
      fee: Money(trade.feeMinor, currency).toDecimal(),
      occurredAt: trade.occurredAt,
    );

List<Holding> buildHoldings(
  List<Asset> assets,
  List<Trade> trades,
  Map<String, PriceSnapshot> latestPrices,
) {
  const calculator = CostBasisCalculator();
  final tradesByAsset = <String, List<Trade>>{};
  for (final t in trades) {
    tradesByAsset.putIfAbsent(t.assetId, () => []).add(t);
  }

  final holdings = <Holding>[];
  for (final asset in assets) {
    final inputs = [
      for (final t in tradesByAsset[asset.id] ?? const <Trade>[])
        toTradeInput(t, asset.currency),
    ];
    final price = latestPrices[asset.id];
    holdings.add(
      Holding(
        asset: asset,
        position: calculator.compute(inputs),
        latestPrice: price?.price,
        priceAt: price?.fetchedAt,
      ),
    );
  }
  holdings.sort((a, b) => a.asset.symbol.compareTo(b.asset.symbol));
  return holdings;
}

/// Ringkasan seluruh portofolio dalam IDR.
class PortfolioSummary {
  const PortfolioSummary({
    required this.valueMinor,
    required this.costMinor,
    required this.unrealizedMinor,
    required this.unpricedCount,
    required this.missingFx,
  });

  /// Nilai pasar total. Aset tanpa harga dinilai pada modalnya.
  final int valueMinor;
  final int costMinor;

  /// Untung/rugi belum terealisasi, hanya dari aset yang punya harga.
  final int unrealizedMinor;

  /// Jumlah aset yang dimiliki tapi belum punya harga.
  final int unpricedCount;

  /// Currency yang kursnya belum ada, sehingga asetnya belum terhitung.
  final Set<String> missingFx;
}

PortfolioSummary summarizePortfolio(List<Holding> holdings, FxTable fx) {
  var value = 0;
  var cost = 0;
  var unrealized = 0;
  var unpriced = 0;
  final missing = <String>{};

  for (final h in holdings) {
    if (!h.isHeld) continue;
    final currency = h.asset.currency;
    final marketValue = h.marketValue;
    final valueBase =
        fx.decimalToBaseMinor(marketValue ?? h.position.totalCost, currency);
    final costBase = fx.decimalToBaseMinor(h.position.totalCost, currency);
    if (valueBase == null || costBase == null) {
      missing.add(currency);
      continue;
    }
    value += valueBase;
    cost += costBase;
    if (marketValue == null) {
      unpriced++;
    } else {
      unrealized += valueBase - costBase;
    }
  }

  return PortfolioSummary(
    valueMinor: value,
    costMinor: cost,
    unrealizedMinor: unrealized,
    unpricedCount: unpriced,
    missingFx: missing,
  );
}
