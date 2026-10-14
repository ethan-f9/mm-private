import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_providers.dart';
import 'package:personal_finance_manager/features/advisor/domain/allocation_presets.dart';

/// Target alokasi dalam persen bulat. Risk profile hanya memilih preset;
/// angkanya bisa kamu ubah, dan total harus 100%.
class AllocationTargetsPage extends ConsumerStatefulWidget {
  const AllocationTargetsPage({super.key});

  @override
  ConsumerState<AllocationTargetsPage> createState() =>
      _AllocationTargetsPageState();
}

class _AllocationTargetsPageState extends ConsumerState<AllocationTargetsPage> {
  final _controllers = {
    for (final k in assetClassKeys) k: TextEditingController(),
  };
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Map<String, int> bps) {
    for (final key in assetClassKeys) {
      final value = bps[key] ?? 0;
      _controllers[key]!.text = value == 0 ? '0' : (value / 100).toString().replaceAll(RegExp(r'\.0$'), '');
    }
  }

  /// Persen per kelas (basis points); null kalau ada isian tidak valid.
  Map<String, int>? _parse() {
    final result = <String, int>{};
    for (final key in assetClassKeys) {
      final raw = _controllers[key]!.text.trim().replaceAll(',', '.');
      final value = double.tryParse(raw);
      if (value == null || value < 0 || value > 100) return null;
      result[key] = (value * 100).round();
    }
    return result;
  }

  Future<void> _save() async {
    final bps = _parse();
    if (bps == null) {
      showSnack(context, 'Isi tiap kelas dengan angka 0 sampai 100');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(allocationRepositoryProvider).save(bps);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final targets = ref.watch(allocationTargetsProvider);

    // Muat target tersimpan sekali, saat data pertama tiba.
    final saved = targets.valueOrNull;
    if (!_loaded && saved != null) {
      _loaded = true;
      if (saved.isNotEmpty) _fill(saved);
    }

    final parsed = _parse();
    final total = parsed == null
        ? null
        : parsed.values.fold<int>(0, (s, v) => s + v) / 100;
    final totalOk = total != null && (total - 100).abs() < 0.001;

    return Scaffold(
      appBar: AppBar(title: const Text('Target alokasi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Pilih preset sebagai titik awal, lalu ubah sesuai keinginanmu. '
            'Advisor membandingkan alokasi aktualmu dengan target ini.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final p in allocationPresets)
                ActionChip(
                  label: Text(p.name),
                  onPressed: () => setState(() => _fill(p.bps)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          for (final key in assetClassKeys) ...[
            TextField(
              controller: _controllers[key],
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: assetClassLabel(key),
                suffixText: '%',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            total == null
                ? 'Total: isian tidak valid'
                : 'Total: ${total.toStringAsFixed(1).replaceAll('.', ',')}%'
                    '${totalOk ? '' : ' (harus 100%)'}',
            style: text.titleSmall?.copyWith(
              color: totalOk ? null : Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_saving || !totalOk) ? null : _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
