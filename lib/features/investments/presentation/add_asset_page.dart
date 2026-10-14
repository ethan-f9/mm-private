import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/presentation/investment_labels.dart';

class AddAssetPage extends ConsumerStatefulWidget {
  const AddAssetPage({super.key});

  @override
  ConsumerState<AddAssetPage> createState() => _AddAssetPageState();
}

class _AddAssetPageState extends ConsumerState<AddAssetPage> {
  final _symbol = TextEditingController();
  final _name = TextEditingController();
  final _externalId = TextEditingController();
  AssetType _type = AssetType.stock;
  String _currency = CurrencyMeta.baseCurrency;
  bool _saving = false;

  @override
  void dispose() {
    _symbol.dispose();
    _name.dispose();
    _externalId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final asset = await ref.read(assetRepositoryProvider).create(
            type: _type,
            symbol: _symbol.text,
            name: _name.text,
            currency: _currency,
            externalId: _externalId.text,
          );
      if (!mounted) return;
      context.pushReplacement('/assets/${asset.id}');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e));
      setState(() => _saving = false);
    }
  }

  String get _symbolHint {
    switch (_type) {
      case AssetType.stock:
        return 'BBCA';
      case AssetType.crypto:
        return 'BTC';
      case AssetType.fund:
        return 'Kode reksadana';
      case AssetType.gold:
        return 'EMAS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Aset')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Jenis', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in AssetType.values)
                ChoiceChip(
                  avatar: Icon(assetTypeIcon(t), size: 18),
                  label: Text(assetTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _symbol,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Kode',
              hintText: _symbolHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Mata uang harga', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in CurrencyMeta.supportedCodes)
                ChoiceChip(
                  label: Text(c),
                  selected: _currency == c,
                  onSelected: (_) => setState(() => _currency = c),
                ),
            ],
          ),
          if (_type == AssetType.crypto) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _externalId,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'ID CoinGecko (opsional)',
                helperText: 'Contoh: bitcoin, ethereum. Diisi = harga otomatis.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _type == AssetType.gold
                ? 'Emas dinilai per gram memakai harga buyback (harga jual '
                    'kembali), bukan harga beli. Isi harganya manual.'
                : (_type == AssetType.crypto
                    ? 'Tanpa ID CoinGecko, harga diisi manual.'
                    : 'Harga saham IDX dan reksadana diisi manual.'),
            style: text.bodySmall,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
