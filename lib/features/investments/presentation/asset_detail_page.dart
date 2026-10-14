import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/money/money.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:personal_finance_manager/features/investments/presentation/investment_labels.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';

class AssetDetailPage extends ConsumerWidget {
  const AssetDetailPage({super.key, required this.assetId});

  final String assetId;

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteAsset(BuildContext context, WidgetRef ref) async {
    if (!await _confirm(context, 'Hapus aset?', 'Aset ini akan dihapus.')) return;
    try {
      await ref.read(assetRepositoryProvider).delete(assetId);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }

  Future<bool> _deleteTrade(BuildContext context, WidgetRef ref, Trade trade) async {
    if (!await _confirm(
      context,
      'Hapus transaksi?',
      'Posisi dan saldo akun pendanaan dihitung ulang.',
    )) {
      return false;
    }
    try {
      await ref.read(tradeRepositoryProvider).deleteTrade(trade.id);
      return true;
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final List<Holding> holdings = ref.watch(holdingsProvider).valueOrNull ?? const [];
    final Holding? holding = holdings.where((h) => h.asset.id == assetId).firstOrNull;
    final List<Trade> allTrades = ref.watch(allTradesProvider).valueOrNull ?? const [];
    final trades = allTrades.where((t) => t.assetId == assetId).toList();
    final List<Account> accounts =
        ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final accountNames = {for (final a in accounts) a.id: a.name};

    if (holding == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aset')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final asset = holding.asset;
    final currency = asset.currency;
    final position = holding.position;
    final value = holding.marketValue;
    final gain = holding.unrealizedGain;
    final percent = holding.unrealizedPercent;
    final dayFormat = DateFormat('d MMM y', 'id_ID');

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: text.bodyMedium)),
              value,
            ],
          ),
        );

    Widget money(Decimal? d, {Color? color}) => d == null
        ? Text('-', style: text.bodyMedium)
        : AmountText(
            minor: decimalToMinor(d, currency),
            currency: currency,
            style: text.bodyMedium?.copyWith(color: color),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('${asset.symbol} \u2022 ${asset.name}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _deleteAsset(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Hapus aset')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/assets/$assetId/trade'),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
        children: [
          line('Unit dimiliki', Text('${position.units}', style: text.bodyMedium)),
          line('Harga beli rata-rata', money(position.averageCost)),
          line('Total modal', money(position.totalCost)),
          line(
            holding.latestPrice == null
                ? 'Harga terakhir'
                : 'Harga terakhir (${ageLabel(holding.priceAt!, DateTime.now())})',
            holding.latestPrice == null
                ? Text('belum diisi', style: text.bodyMedium)
                : money(holding.latestPrice),
          ),
          line('Nilai pasar', money(value)),
          line(
            'Untung/rugi belum terealisasi'
            '${percent == null ? '' : ' (${formatPercent(percent)})'}',
            money(
              gain,
              color: gain == null
                  ? null
                  : (gain.signum < 0 ? Colors.red : Colors.green.shade600),
            ),
          ),
          line('Untung/rugi terealisasi', money(position.realizedGain)),
          line('Dividen diterima', money(position.dividendIncome)),
          if (asset.externalId != null)
            line('ID CoinGecko', Text(asset.externalId!, style: text.bodyMedium)),
          const SizedBox(height: 16),
          Text('Transaksi', style: text.titleMedium),
          const SizedBox(height: 8),
          if (trades.isEmpty)
            Text('Belum ada transaksi. Tekan + untuk mencatat.', style: text.bodySmall),
          for (final t in trades)
            Dismissible(
              key: ValueKey('trade-${t.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _deleteTrade(context, ref, t),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${tradeSideLabel(t.side)} ${t.quantity} \u00d7 '
                  '${formatDecimalMoney(t.price, currency)}',
                ),
                subtitle: Text(
                  [
                    dayFormat.format(t.occurredAt),
                    if (t.fundingAccountId != null)
                      accountNames[t.fundingAccountId] ?? '-',
                    if (t.feeMinor > 0) 'fee ${formatDecimalMoney(Money(t.feeMinor, currency).toDecimal(), currency)}',
                  ].join(' \u2022 '),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
