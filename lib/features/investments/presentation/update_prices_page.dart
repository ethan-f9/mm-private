import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/price_input.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/presentation/investment_labels.dart';

/// Isi harga terbaru per aset (saham IDX, reksadana, emas, dan crypto tanpa
/// harga otomatis). Hanya kolom yang diubah yang disimpan.
class UpdatePricesPage extends ConsumerStatefulWidget {
  const UpdatePricesPage({super.key});

  @override
  ConsumerState<UpdatePricesPage> createState() => _UpdatePricesPageState();
}

class _UpdatePricesPageState extends ConsumerState<UpdatePricesPage> {
  final _controllers = <String, TextEditingController>{};
  final _initial = <String, String>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Asset asset, PriceSnapshot? latest) {
    return _controllers.putIfAbsent(asset.id, () {
      final initial = latest == null ? '' : latest.price.toString();
      _initial[asset.id] = initial;
      return TextEditingController(text: initial);
    });
  }

  Future<void> _save(List<Asset> assets) async {
    final repo = ref.read(priceRepositoryProvider);
    var saved = 0;
    setState(() => _saving = true);
    try {
      for (final asset in assets) {
        final controller = _controllers[asset.id];
        if (controller == null) continue;
        final text = controller.text.trim();
        if (text == (_initial[asset.id] ?? '') || text.isEmpty) continue;

        final price = parsePrice(text, asset.currency);
        if (price == null) {
          throw ArgumentError('Harga ${asset.symbol} tidak valid: "$text"');
        }
        await repo.saveManual(asset.id, price);
        saved++;
      }
      if (!mounted) return;
      if (saved == 0) {
        showSnack(context, 'Tidak ada harga yang diubah');
        setState(() => _saving = false);
      } else {
        showSnack(context, '$saved harga disimpan');
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final List<Asset> assets = ref.watch(assetsProvider).valueOrNull ?? const [];
    final Map<String, PriceSnapshot> latest =
        ref.watch(latestPricesProvider).valueOrNull ?? const {};
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Isi harga manual')),
      body: assets.isEmpty
          ? const Center(child: Text('Belum ada aset.'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Emas: isi harga buyback per gram, bukan harga beli. '
                  'Harga crypto dengan ID CoinGecko diperbarui otomatis, tapi '
                  'tetap bisa kamu timpa di sini.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 16),
                for (final a in assets) ...[
                  TextField(
                    controller: _controllerFor(a, latest[a.id]),
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: '${a.symbol} \u2022 ${a.name}',
                      prefixText: '${a.currency} ',
                      helperText: latest[a.id] == null
                          ? 'Belum pernah diisi'
                          : 'Terakhir ${ageLabel(latest[a.id]!.fetchedAt, now)} '
                              '(${latest[a.id]!.source})'
                              '${a.priceSource == PriceSource.auto ? ' \u2022 otomatis' : ''}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : () => _save(assets),
                  child: const Text('Simpan'),
                ),
              ],
            ),
    );
  }
}
