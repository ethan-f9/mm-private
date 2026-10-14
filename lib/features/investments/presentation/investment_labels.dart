import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/money.dart';
import 'package:personal_finance_manager/core/money/money_format.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';

String assetTypeLabel(AssetType type) {
  switch (type) {
    case AssetType.stock:
      return 'Saham';
    case AssetType.crypto:
      return 'Crypto';
    case AssetType.fund:
      return 'Reksadana';
    case AssetType.gold:
      return 'Emas';
  }
}

IconData assetTypeIcon(AssetType type) {
  switch (type) {
    case AssetType.stock:
      return Icons.show_chart;
    case AssetType.crypto:
      return Icons.currency_bitcoin;
    case AssetType.fund:
      return Icons.pie_chart_outline;
    case AssetType.gold:
      return Icons.diamond_outlined;
  }
}

String tradeSideLabel(TradeSide side) {
  switch (side) {
    case TradeSide.buy:
      return 'Beli';
    case TradeSide.sell:
      return 'Jual';
    case TradeSide.dividend:
      return 'Dividen';
  }
}

/// Untuk teks biasa. Tampilan nominal yang harus ikut Stealth Mode memakai
/// AmountText dengan minor unit dari [decimalToMinor].
String formatDecimalMoney(Decimal amount, String currency) =>
    formatMinor(decimalToMinor(amount, currency), currency);

int decimalToMinor(Decimal amount, String currency) =>
    Money.fromDecimal(amount, currency).minor;

String formatPercent(double value) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1).replaceAll('.', ',')}%';
}

/// "3 hari lalu", "hari ini", dst.
String ageLabel(DateTime at, DateTime now) {
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'hari ini';
  if (days == 1) return 'kemarin';
  return '$days hari lalu';
}
