import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/money/money_format.dart';

/// Stealth Mode: kalau aktif, semua nominal tampil sebagai ****.
/// State ini belum disimpan permanen (reset saat app dibuka ulang).
final stealthModeProvider = StateProvider<bool>((ref) => false);

class AmountText extends ConsumerWidget {
  const AmountText({
    super.key,
    required this.minor,
    required this.currency,
    this.style,
  });

  final int minor;
  final String currency;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(stealthModeProvider);
    return Text(hidden ? '****' : formatMinor(minor, currency), style: style);
  }
}
