import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final stealth = ref.watch(stealthModeProvider);
    final accounts = ref.watch(accountsProvider);
    final balances = ref.watch(accountBalancesProvider).valueOrNull ?? const {};
    final month = ref.watch(selectedMonthProvider);
    final ledger = ref.watch(ledgerProvider(month)).valueOrNull ?? const [];

    // Total saldo per currency. Konversi kurs ke IDR menyusul di fase 2,
    // jadi currency asing ditampilkan terpisah, tidak dijumlahkan.
    final totals = <String, int>{};
    for (final Account a in accounts.valueOrNull ?? const <Account>[]) {
      totals[a.currency] =
          (totals[a.currency] ?? 0) + (balances[a.id] ?? a.openingBalanceMinor);
    }
    final base = CurrencyMeta.baseCurrency;
    final others = totals.entries.where((e) => e.key != base).toList();

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
            icon: Icon(stealth ? Icons.visibility_off : Icons.visibility),
            tooltip: 'Stealth mode',
            onPressed: () =>
                ref.read(stealthModeProvider.notifier).state = !stealth,
          ),
        ],
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) {
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
              Text('Total saldo ($base)', style: text.labelLarge),
              const SizedBox(height: 8),
              AmountText(
                minor: totals[base] ?? 0,
                currency: base,
                style: text.displaySmall,
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Currency lain (belum dikonversi)', style: text.labelLarge),
                const SizedBox(height: 4),
                for (final e in others)
                  AmountText(
                    minor: e.value,
                    currency: e.key,
                    style: text.titleMedium,
                  ),
              ],
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
