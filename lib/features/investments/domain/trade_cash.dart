import 'package:decimal/decimal.dart';
import 'package:personal_finance_manager/core/money/money.dart';

import 'trade_side.dart';

/// Dampak trade ke saldo akun pendanaan (minor unit, dalam currency aset
/// yang harus sama dengan currency akun):
/// - beli: keluar (jumlah x harga + fee)
/// - jual: masuk (jumlah x harga - fee)
/// - dividen: masuk (jumlah x harga - fee)
int tradeCashDeltaMinor({
  required TradeSide side,
  required Decimal quantity,
  required Decimal price,
  required int feeMinor,
  required String currency,
}) {
  final gross = Money.fromDecimal(quantity * price, currency).minor;
  switch (side) {
    case TradeSide.buy:
      return -(gross + feeMinor);
    case TradeSide.sell:
    case TradeSide.dividend:
      return gross - feeMinor;
  }
}
