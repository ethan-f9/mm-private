import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_filter.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _updateFilter(LedgerFilter Function(LedgerFilter current) change) {
    final notifier = ref.read(ledgerFilterProvider.notifier);
    notifier.state = change(notifier.state);
  }

  void _shiftMonth(DateTime month, int delta) {
    ref.read(selectedMonthProvider.notifier).state =
        DateTime(month.year, month.month + delta);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final range = LedgerRange(
      DateTime(picked.start.year, picked.start.month, picked.start.day),
      DateTime(picked.end.year, picked.end.month, picked.end.day + 1),
    );
    _updateFilter((f) => f.copyWith(range: range));
  }

  Future<bool> _confirmDelete() async {
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

  static String _kindLabel(LedgerKind kind) {
    switch (kind) {
      case LedgerKind.all:
        return 'Semua';
      case LedgerKind.expense:
        return 'Pengeluaran';
      case LedgerKind.income:
        return 'Pemasukan';
      case LedgerKind.transfer:
        return 'Transfer';
    }
  }

  Widget _periodBar(LedgerFilter filter, DateTime month) {
    final text = Theme.of(context).textTheme;
    final dateFormat = DateFormat('d MMM y', 'id_ID');

    final range = filter.range;
    if (range != null) {
      final lastDay = DateTime(range.to.year, range.to.month, range.to.day - 1);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${dateFormat.format(range.from)} \u2013 ${dateFormat.format(lastDay)}',
                style: text.titleSmall,
              ),
            ),
            TextButton(
              onPressed: () => _updateFilter((f) => f.copyWith(clearRange: true)),
              child: const Text('Hapus rentang'),
            ),
          ],
        ),
      );
    }

    if (filter.isSearching) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Mencari di semua tanggal', style: text.bodySmall),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftMonth(month, -1),
        ),
        Text(DateFormat.yMMMM('id_ID').format(month), style: text.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _shiftMonth(month, 1),
        ),
      ],
    );
  }

  Widget _dismissBackground() {
    return Container(
      color: Colors.red,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Widget _transactionTile(
    TransactionRow row,
    Map<String, String> accountNames,
    Map<String, String> categoryNames,
  ) {
    final text = Theme.of(context).textTheme;
    final isIncome = row.kind == TxKind.income;
    final note = row.note ?? '';
    final category = categoryNames[row.categoryId];
    final title = note.isNotEmpty ? note : (category ?? 'Tanpa kategori');
    final subtitle = <String>[
      accountNames[row.accountId] ?? '-',
      if (note.isNotEmpty && category != null) category,
    ].join(' \u2022 ');

    return Dismissible(
      key: ValueKey('tx-${row.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) =>
          ref.read(transactionRepositoryProvider).deleteTransaction(row.id),
      background: _dismissBackground(),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => context.push('/edit-transaction', extra: row),
        trailing: AmountText(
          minor: isIncome ? row.amountMinor : -row.amountMinor,
          currency: row.currency,
          style: text.titleSmall?.copyWith(
            color: isIncome ? Colors.green.shade600 : null,
          ),
        ),
      ),
    );
  }

  Widget _transferTile(
    Transfer transfer,
    List<Account> accounts,
    Map<String, String> accountNames,
  ) {
    final text = Theme.of(context).textTheme;
    final from = accountNames[transfer.fromAccountId] ?? '-';
    final to = accountNames[transfer.toAccountId] ?? '-';
    final fromCurrency = accounts
            .where((a) => a.id == transfer.fromAccountId)
            .firstOrNull
            ?.currency ??
        CurrencyMeta.baseCurrency;
    final note = transfer.note ?? '';

    return Dismissible(
      key: ValueKey('tf-${transfer.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) =>
          ref.read(transactionRepositoryProvider).deleteTransfer(transfer.id),
      background: _dismissBackground(),
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text('$from \u2192 $to'),
        subtitle: Text(note.isNotEmpty ? note : 'Transfer'),
        trailing: AmountText(
          minor: transfer.fromAmountMinor,
          currency: fromCurrency,
          style: text.titleSmall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(ledgerFilterProvider);
    final month = ref.watch(selectedMonthProvider);
    final range = effectiveRange(filter, month);
    final ledger = ref.watch(rangeLedgerProvider(range));
    final List<Account> accounts =
        ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final List<Category> categories =
        ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pilih rentang tanggal',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Column(
        children: [
          _periodBar(filter, month),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (v) => _updateFilter((f) => f.copyWith(query: v)),
              decoration: InputDecoration(
                hintText: 'Cari catatan atau kategori',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _updateFilter((f) => f.copyWith(query: ''));
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final k in LedgerKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_kindLabel(k)),
                      selected: filter.kind == k,
                      onSelected: (_) => _updateFilter((f) => f.copyWith(kind: k)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ledger.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorMessage(e))),
              data: (items) {
                final filtered =
                    applyLedgerFilter(items, filter, categoryNames: categoryNames);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      filter.isSearching
                          ? 'Tidak ada hasil untuk "${filter.query.trim()}".'
                          : 'Belum ada transaksi.',
                    ),
                  );
                }

                final rows = <Object>[];
                for (final group in groupByDay(filtered)) {
                  rows.add(group);
                  rows.addAll(group.items);
                }

                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final entry = rows[i];
                    if (entry is DayGroup) return _DayHeader(group: entry);
                    final item = entry as LedgerItem;
                    switch (item) {
                      case TransactionItem(:final row):
                        return _transactionTile(row, accountNames, categoryNames);
                      case TransferItem(:final transfer):
                        return _transferTile(transfer, accounts, accountNames);
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

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final DayGroup group;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final net = dailyNetMinor(group, CurrencyMeta.baseCurrency);

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat('EEEE, d MMM', 'id_ID').format(group.day),
              style: text.labelLarge,
            ),
          ),
          if (net != null)
            AmountText(
              minor: net,
              currency: CurrencyMeta.baseCurrency,
              style: text.labelMedium,
            ),
        ],
      ),
    );
  }
}
