import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/money/amount_input.dart';
import 'package:personal_finance_manager/core/money/price_input.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/balance_hint.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_cash.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:personal_finance_manager/features/investments/presentation/investment_labels.dart';

class AddTradePage extends ConsumerStatefulWidget {
  const AddTradePage({super.key, required this.assetId});

  final String assetId;

  @override
  ConsumerState<AddTradePage> createState() => _AddTradePageState();
}

class _AddTradePageState extends ConsumerState<AddTradePage> {
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _fee = TextEditingController();
  TradeSide _side = TradeSide.buy;
  String? _fundingAccountId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(Asset asset) async {
    final quantity = parseQuantity(_quantity.text);
    if (quantity == null) {
      showSnack(context, 'Jumlah unit tidak valid');
      return;
    }
    final price = parsePrice(_price.text, asset.currency);
    if (price == null) {
      showSnack(context, 'Harga tidak valid');
      return;
    }
    var feeMinor = 0;
    if (_fee.text.trim().isNotEmpty) {
      final parsed = parseAmountMinor(_fee.text, asset.currency);
      if (parsed == null) {
        showSnack(context, 'Fee tidak valid');
        return;
      }
      feeMinor = parsed;
    }

    setState(() => _saving = true);
    try {
      await ref.read(tradeRepositoryProvider).addTrade(
            assetId: asset.id,
            side: _side,
            quantity: quantity,
            price: price,
            feeMinor: feeMinor,
            fundingAccountId: _fundingAccountId,
            occurredAt: withCurrentTime(_date),
          );
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
    final List<Asset> assets = ref.watch(assetsProvider).valueOrNull ?? const [];
    final Asset? asset = assets.where((a) => a.id == widget.assetId).firstOrNull;
    if (asset == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaksi Aset')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<Account> accounts =
        ref.watch(accountsProvider).valueOrNull ?? const [];
    final Map<String, int> balances =
        ref.watch(accountBalancesProvider).valueOrNull ?? const {};
    final candidates = accounts.where((a) => a.currency == asset.currency).toList();
    final Account? funding =
        candidates.where((a) => a.id == _fundingAccountId).firstOrNull;

    final quantity = parseQuantity(_quantity.text);
    final price = parsePrice(_price.text, asset.currency);
    final feeMinor = _fee.text.trim().isEmpty
        ? 0
        : (parseAmountMinor(_fee.text, asset.currency) ?? 0);

    int? cashDelta;
    if (quantity != null && price != null) {
      cashDelta = tradeCashDeltaMinor(
        side: _side,
        quantity: quantity,
        price: price,
        feeMinor: feeMinor,
        currency: asset.currency,
      );
    }

    final isDividend = _side == TradeSide.dividend;

    return Scaffold(
      appBar: AppBar(title: Text('${asset.symbol} \u2022 Transaksi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SegmentedButton<TradeSide>(
            segments: [
              for (final s in TradeSide.values)
                ButtonSegment(value: s, label: Text(tradeSideLabel(s))),
            ],
            selected: {_side},
            onSelectionChanged: (s) => setState(() => _side = s.first),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: isDividend ? 'Jumlah unit yang dimiliki' : 'Jumlah unit',
              helperText: asset.type.name == 'gold' ? 'Dalam gram' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _price,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: isDividend ? 'Dividen per unit' : 'Harga per unit',
              prefixText: '${asset.currency} ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _fee,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Fee / pajak (opsional)',
              prefixText: '${asset.currency} ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _side == TradeSide.buy
                ? 'Dibayar dari akun (opsional)'
                : 'Masuk ke akun (opsional)',
            style: text.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tanpa akun'),
                selected: _fundingAccountId == null,
                onSelected: (_) => setState(() => _fundingAccountId = null),
              ),
              for (final a in candidates)
                ChoiceChip(
                  label: Text(a.name),
                  selected: _fundingAccountId == a.id,
                  onSelected: (_) => setState(() => _fundingAccountId = a.id),
                ),
            ],
          ),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Tidak ada akun bermata uang ${asset.currency}. '
                'Transaksi tidak akan mengubah saldo akun mana pun.',
                style: text.bodySmall,
              ),
            ),
          if (funding != null) ...[
            const SizedBox(height: 8),
            BalanceHint(
              label: 'Saldo ${funding.name}',
              balanceMinor: balances[funding.id] ?? funding.openingBalanceMinor,
              currency: funding.currency,
              afterMinor: cashDelta == null
                  ? null
                  : (balances[funding.id] ?? funding.openingBalanceMinor) + cashDelta,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(DateFormat('EEEE, d MMMM y', 'id_ID').format(_date)),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : () => _save(asset),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
