import 'package:flutter/material.dart';
import 'package:personal_finance_manager/core/db/enums.dart';

String errorMessage(Object error) {
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Input tidak valid';
  }
  return error.toString();
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String accountTypeLabel(AccountType type) {
  switch (type) {
    case AccountType.cash:
      return 'Tunai';
    case AccountType.bank:
      return 'Bank';
    case AccountType.ewallet:
      return 'E-Wallet';
    case AccountType.foreign:
      return 'Valas';
  }
}

IconData accountTypeIcon(AccountType type) {
  switch (type) {
    case AccountType.cash:
      return Icons.payments_outlined;
    case AccountType.bank:
      return Icons.account_balance_outlined;
    case AccountType.ewallet:
      return Icons.account_balance_wallet_outlined;
    case AccountType.foreign:
      return Icons.currency_exchange;
  }
}

/// Tanggal pilihan user + jam sekarang, supaya urutan di hari yang sama
/// masuk akal.
DateTime withCurrentTime(DateTime date) {
  final now = DateTime.now();
  return DateTime(date.year, date.month, date.day, now.hour, now.minute);
}
