import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/investments/data/investment_providers.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';
import 'package:personal_finance_manager/features/networth/presentation/net_worth_chart_card.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final stealth = ref.watch(stealthModeProvider);
    final accounts = ref.watch(accountsProvider);
    final netWorth = ref.watch(netWorthProvider);
    final month = ref.watch(selectedMonthProvider);
    final List<LedgerItem> ledger =
        ref.watch(ledgerProvider(month)).valueOrNull ?? const <LedgerItem>[];
    final lastBackup = ref.watch(lastBackupProvider);
    // Banner hanya muncul setelah status backup selesai dimuat (tanpa kedip).
    final needsBackup = lastBackup.hasValue &&
        (lastBackup.value == null ||
            DateTime.now().difference(lastBackup.value!).inDays >= 7);

    final base = CurrencyMeta.baseCurrency;

    var income = 0;
    var expense = 0;
    for (final item in ledger) {
      if (item is TransactionItem && item.row.currency == base) {
        if (item.row.kind == TxKind.income) {
          income += item.row.amountMinor;
        } else {
          expense += item.row.amountMinor;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ringkasan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: Icon(stealth ? Icons.visibility_off : Icons.visibility),
            tooltip: 'Stealth mode',
            onPressed: () {
              final next = !stealth;
              ref.read(stealthModeProvider.notifier).state = next;
              // Disimpan supaya tetap aktif setelah app dibuka ulang.
              ref
                  .read(settingsRepositoryProvider)
                  .set(stealthSettingKey, next ? '1' : '0');
            },
          ),
        ],
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (List<Account> list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Belum ada akun. Mulai dengan menambah akun pertama.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.push('/add-account'),
                      child: const Text('Tambah akun'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (needsBackup) ...[
                _BackupBanner(lastBackup: lastBackup.value),
                const SizedBox(height: 24),
              ],
              Text('Net worth ($base)', style: text.labelLarge),
              const SizedBox(height: 8),
              netWorth.when(
                loading: () => Text('...', style: text.displaySmall),
                error: (e, _) => Text(errorMessage(e)),
                data: (nw) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AmountText(
                      minor: nw.totalMinor,
                      currency: base,
                      style: text.displaySmall,
                    ),
                    const SizedBox(height: 16),
                    const NetWorthChartCard(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryTile(
                            label: 'Kas dan akun',
                            minor: nw.cashMinor,
                            currency: base,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryTile(
                            label: 'Investasi',
                            minor: nw.investmentsMinor,
                            currency: base,
                          ),
                        ),
                      ],
                    ),
                    if (!nw.isComplete) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Total belum lengkap: kurs ${nw.missingFx.join(', ')} '
                        'belum tersedia. Buka tab Investasi dan tekan ikon '
                        'sinkronisasi (perlu internet).',
                        style: text.bodySmall?.copyWith(color: Colors.red),
                      ),
                    ],
                    if (nw.unpricedCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${nw.unpricedCount} aset belum punya harga dan dinilai '
                        'pada harga beli.',
                        style: text.bodySmall?.copyWith(color: Colors.orange.shade700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text('Bulan ini ($base)', style: text.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      label: 'Pemasukan',
                      minor: income,
                      currency: base,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryTile(
                      label: 'Pengeluaran',
                      minor: expense,
                      currency: base,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: () => context.push('/advisor'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insights_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Advisor: runway, tren pengeluaran, alokasi aset',
                          style: text.bodyMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.minor,
    required this.currency,
  });

  final String label;
  final int minor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(height: 4),
          AmountText(minor: minor, currency: currency, style: text.titleMedium),
        ],
      ),
    );
  }
}

class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.lastBackup});

  final DateTime? lastBackup;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final last = lastBackup;
    final message = last == null
        ? 'Belum pernah backup. Datamu hanya ada di HP ini.'
        : 'Backup terakhir ${DateTime.now().difference(last).inDays} hari lalu.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: text.bodyMedium)),
          TextButton(
            onPressed: () => context.push('/backup'),
            child: const Text('Backup'),
          ),
        ],
      ),
    );
  }
}
