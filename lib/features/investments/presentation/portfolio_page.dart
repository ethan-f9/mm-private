import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/presentation/investment_labels.dart';
import 'package:personal_finance_manager/features/market/data/market_refresh_service.dart';

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(marketRefreshServiceProvider).refresh();
      ref.invalidate(marketLastRefreshProvider);
      if (!mounted) return;
      if (result.hasErrors) {
        showSnack(context, 'Sebagian gagal: ${result.errors.first}');
      } else if (result.fxUpdated + result.pricesUpdated == 0) {
        showSnack(context, 'Tidak ada yang perlu diperbarui secara otomatis.');
      } else {
        showSnack(
          context,
          'Diperbarui: ${result.fxUpdated} kurs, ${result.pricesUpdated} harga.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final holdings = ref.watch(holdingsProvider);
    final fx = ref.watch(fxTableProvider).valueOrNull ?? FxTable.empty;
    final lastRefresh = ref.watch(marketLastRefreshProvider).valueOrNull;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investasi'),
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Perbarui kurs dan harga crypto',
            onPressed: _busy ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Isi harga manual',
            onPressed: () => context.push('/prices'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah aset',
            onPressed: () => context.push('/assets/new'),
          ),
        ],
      ),
      body: holdings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Belum ada aset. Tekan + di kanan atas untuk menambah '
                  'saham, crypto, reksadana, atau emas.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final summary = summarizePortfolio(list, fx);
          final base = CurrencyMeta.baseCurrency;
          final gainColor = summary.unrealizedMinor >= 0
              ? Colors.green.shade600
              : Colors.red;

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nilai portofolio ($base)', style: text.labelLarge),
                    const SizedBox(height: 8),
                    AmountText(
                      minor: summary.valueMinor,
                      currency: base,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Untung/rugi belum terealisasi: ', style: text.bodySmall),
                        AmountText(
                          minor: summary.unrealizedMinor,
                          currency: base,
                          style: text.bodyMedium?.copyWith(color: gainColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lastRefresh == null
                          ? 'Kurs dan harga otomatis belum pernah diperbarui.'
                          : 'Kurs dan harga otomatis diperbarui '
                              '${ageLabel(lastRefresh, now)}.',
                      style: text.bodySmall,
                    ),
                    if (summary.unpricedCount > 0)
                      Text(
                        '${summary.unpricedCount} aset belum punya harga '
                        '(dinilai pada harga beli). Isi lewat ikon pensil.',
                        style: text.bodySmall?.copyWith(color: Colors.orange.shade700),
                      ),
                    if (summary.missingFx.isNotEmpty)
                      Text(
                        'Kurs belum tersedia untuk ${summary.missingFx.join(', ')}; '
                        'asetnya belum terhitung. Tekan ikon sinkronisasi.',
                        style: text.bodySmall?.copyWith(color: Colors.red),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final h in list) _HoldingTile(holding: h),
            ],
          );
        },
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({required this.holding});

  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final asset = holding.asset;
    final currency = asset.currency;
    final value = holding.marketValue;
    final gain = holding.unrealizedGain;
    final percent = holding.unrealizedPercent;
    final gainColor = Colors.green.shade600;

    return ListTile(
      leading: Icon(assetTypeIcon(asset.type)),
      title: Text('${asset.symbol}  \u2022  ${asset.name}'),
      subtitle: Text(
        holding.isHeld
            ? '${holding.position.units} unit \u2022 rata-rata '
                '${formatDecimalMoney(holding.position.averageCost, currency)}'
            : 'Terjual semua',
      ),
      trailing: !holding.isHeld
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (value == null)
                  Text('Harga belum diisi', style: text.bodySmall)
                else
                  AmountText(
                    minor: decimalToMinor(value, currency),
                    currency: currency,
                    style: text.titleSmall,
                  ),
                if (gain != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AmountText(
                        minor: decimalToMinor(gain, currency),
                        currency: currency,
                        style: text.bodySmall?.copyWith(
                          color: gain.signum < 0 ? Colors.red : gainColor,
                        ),
                      ),
                      if (percent != null)
                        Text(
                          '  ${formatPercent(percent)}',
                          style: text.bodySmall?.copyWith(
                            color: gain.signum < 0 ? Colors.red : gainColor,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
      onTap: () => context.push('/assets/${asset.id}'),
    );
  }
}
