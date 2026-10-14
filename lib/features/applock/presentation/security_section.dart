import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_controller.dart';

/// Bagian "Keamanan" di layar Pengaturan.
class SecuritySection extends ConsumerWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final state = ref.watch(appLockProvider);
    final controller = ref.read(appLockProvider.notifier);

    Future<void> toggleLock(bool enable) async {
      final error = enable ? await controller.enable() : await controller.disable();
      if (error != null && context.mounted) showSnack(context, error);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Keamanan', style: text.titleMedium),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Kunci aplikasi'),
          subtitle: const Text(
            'Minta sidik jari atau PIN/pola HP saat app dibuka.',
          ),
          value: state.enabled,
          onChanged: state.authenticating ? null : toggleLock,
        ),
        if (state.enabled) ...[
          const SizedBox(height: 4),
          Text('Kunci ulang setelah di latar belakang', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final seconds in appLockTimeoutOptions)
                ChoiceChip(
                  label: Text(appLockTimeoutLabel(seconds)),
                  selected: state.timeoutSeconds == seconds,
                  onSelected: (_) => controller.setTimeout(seconds),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Layar aman'),
          subtitle: const Text(
            'Blokir screenshot dan sembunyikan isi app di daftar app terbaru. '
            'Perekam layar (mis. scrcpy) akan menampilkan layar hitam.',
          ),
          value: state.secureScreen,
          onChanged: (value) async {
            final error = await controller.setSecureScreen(value);
            if (error != null && context.mounted) showSnack(context, error);
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Kunci ini mencegah akses santai ke app. Data di HP belum '
          'dienkripsi, jadi ini bukan perlindungan terhadap HP yang di-root '
          'atau diperiksa secara forensik.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
