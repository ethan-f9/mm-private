import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/money/money_format.dart';

/// Stealth Mode: kalau aktif, semua nominal tampil sebagai ****.
/// Nilainya disimpan di tabel pengaturan (kunci [stealthSettingKey]) dan
/// dimuat saat app dibuka (lihat main.dart).
final stealthModeProvider = StateProvider<bool>((ref) => false);

const stealthSettingKey = 'ui.stealth';

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
