import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus?'),
        content: const Text('Saldo akun akan dihitung ulang.'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final ledger = ref.watch(ledgerProvider(month));
    final accounts = ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};
    final dayFormat = DateFormat('d MMM', 'id_ID');
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                    DateTime(month.year, month.month - 1),
              ),
              Text(DateFormat.yMMMM('id_ID').format(month), style: text.titleMedium),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorMessage(e))),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('Belum ada transaksi bulan ini.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    switch (item) {
                      case TransactionItem(:final row):
                        final isIncome = row.kind == TxKind.income;
                        final noteText = row.note ?? '';
                        final title = noteText.isNotEmpty
                            ? noteText
                            : (categoryNames[row.categoryId] ?? 'Tanpa kategori');
                        return Dismissible(
                          key: ValueKey('tx-${row.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmDelete(context),
                          onDismissed: (_) => ref
                              .read(transactionRepositoryProvider)
                              .deleteTransaction(row.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: ListTile(
                            title: Text(title),
                            subtitle: Text(
                              '${accountNames[row.accountId] ?? '-'} \u2022 '
                              '${dayFormat.format(row.occurredAt)}',
                            ),
                            trailing: AmountText(
                              minor: isIncome ? row.amountMinor : -row.amountMinor,
                              currency: row.currency,
                              style: text.titleSmall?.copyWith(
                                color: isIncome ? Colors.green.shade600 : null,
                              ),
                            ),
                          ),
                        );
                      case TransferItem(:final transfer):
                        final from = accountNames[transfer.fromAccountId] ?? '-';
                        final to = accountNames[transfer.toAccountId] ?? '-';
                        final fromCurrency = accounts
                                .where((a) => a.id == transfer.fromAccountId)
                                .firstOrNull
                                ?.currency ??
                            'IDR';
                        return Dismissible(
                          key: ValueKey('tf-${transfer.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmDelete(context),
                          onDismissed: (_) => ref
                              .read(transactionRepositoryProvider)
                              .deleteTransfer(transfer.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.swap_horiz),
                            title: Text('$from \u2192 $to'),
                            subtitle: Text(dayFormat.format(transfer.occurredAt)),
                            trailing: AmountText(
                              minor: transfer.fromAmountMinor,
                              currency: fromCurrency,
                              style: text.titleSmall,
                            ),
                          ),
                        );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
