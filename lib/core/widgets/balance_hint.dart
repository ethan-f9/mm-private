import 'package:flutter/material.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';

/// "Saldo: Rp 1.000.000 -> Rp 750.000". Kalau hasilnya negatif, tampil merah
/// dengan peringatan (tidak memblokir; kartu kredit mungkin memang negatif).
class BalanceHint extends StatelessWidget {
  const BalanceHint({
    super.key,
    required this.label,
    required this.balanceMinor,
    required this.currency,
    this.afterMinor,
  });

  final String label;
  final int balanceMinor;
  final String currency;
  final int? afterMinor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final after = afterMinor;
    final negative = after != null && after < 0;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('$label:', style: text.bodySmall),
        AmountText(minor: balanceMinor, currency: currency, style: text.bodyMedium),
        if (after != null) ...[
          const Text('\u2192'),
          AmountText(
            minor: after,
            currency: currency,
            style: text.bodyMedium?.copyWith(color: negative ? Colors.red : null),
          ),
          if (negative)
            Text(
              'saldo tidak cukup',
              style: text.bodySmall?.copyWith(color: Colors.red),
            ),
        ],
      ],
    );
  }
}
