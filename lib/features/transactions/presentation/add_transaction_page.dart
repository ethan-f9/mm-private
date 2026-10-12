import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/amount_input.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/balance_hint.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_text_parser.dart';

class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({super.key});

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  final _aiText = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TxKind _kind = TxKind.expense;
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _aiBusy = false;

  @override
  void dispose() {
    _aiText.dispose();
    _amount.dispose();
    _note.dispose();
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

  Future<void> _fillWithAi(
    List<Account> accounts,
    List<Category> categories,
  ) async {
    final input = _aiText.text.trim();
    if (input.isEmpty) return;

    final key = await ref.read(secureStoreProvider).readAiKey();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      showSnack(context, 'Atur API key AI di Pengaturan dulu');
      return;
    }

    setState(() => _aiBusy = true);
    try {
      final result = await ref.read(transactionTextParserProvider).parse(
            input,
            accounts: accounts,
            categories: categories,
            today: DateTime.now(),
          );
      if (!mounted) return;
      setState(() {
        _kind = result.kind;
        if (result.accountId != null) _accountId = result.accountId;
        _categoryId = result.categoryId;
        final amountText = result.amountText;
        if (amountText != null) _amount.text = amountText;
        final note = result.note;
        if (note != null) _note.text = note;
        final date = result.date;
        if (date != null) _date = date;
        _aiBusy = false;
      });
      showSnack(context, 'Cek hasilnya, lalu tekan Simpan');
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiBusy = false);
      showSnack(context, 'AI gagal: ${errorMessage(e)}');
    }
  }

  Future<void> _save(String? accountId, String? currency) async {
    if (accountId == null || currency == null) {
      showSnack(context, 'Pilih akun dulu');
      return;
    }
    final minor = parseAmountMinor(_amount.text, currency);
    if (minor == null) {
      showSnack(context, 'Nominal tidak valid (contoh: 25k, 1,5jt, 25000)');
      return;
    }

    setState(() => _saving = true);
    try {
      final note = _note.text.trim();
      await ref.read(transactionRepositoryProvider).addTransaction(
            accountId: accountId,
            kind: _kind,
            amountMinor: minor,
            occurredAt: withCurrentTime(_date),
            categoryId: _categoryId,
            note: note.isEmpty ? null : note,
            source: _aiText.text.trim().isEmpty ? TxSource.manual : TxSource.ai,
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
    final List<Account> accounts =
        ref.watch(accountsProvider).valueOrNull ?? const [];
    final List<Category> categories =
        ref.watch(categoriesProvider).valueOrNull ?? const [];
    final Map<String, int> balances =
        ref.watch(accountBalancesProvider).valueOrNull ?? const {};

    final Account? selected = _accountId == null
        ? accounts.firstOrNull
        : (accounts.where((a) => a.id == _accountId).firstOrNull ??
            accounts.firstOrNull);
    final accountId = selected?.id;
    final currency = selected?.currency;

    final balance =
        selected == null ? null : (balances[selected.id] ?? selected.openingBalanceMinor);
    final amountMinor =
        currency == null ? null : parseAmountMinor(_amount.text, currency);
    final int? after = (balance == null || amountMinor == null)
        ? null
        : (_kind == TxKind.expense ? balance - amountMinor : balance + amountMinor);

    final visibleCategories =
        categories.where((c) => c.kind.name == _kind.name).toList();

    if (accounts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tambah Transaksi')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Buat akun dulu sebelum mencatat transaksi.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pushReplacement('/add-account'),
                  child: const Text('Tambah akun'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Transaksi')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _aiText,
            enabled: !_aiBusy,
            decoration: InputDecoration(
              labelText: 'Isi dengan AI',
              hintText: 'nasi padang 25k pakai gopay',
              border: const OutlineInputBorder(),
              suffixIcon: _aiBusy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.auto_awesome),
                      tooltip: 'Isi otomatis',
                      onPressed: () => _fillWithAi(accounts, categories),
                    ),
            ),
            onSubmitted: (_) => _fillWithAi(accounts, categories),
          ),
          const SizedBox(height: 24),
          SegmentedButton<TxKind>(
            segments: const [
              ButtonSegment(value: TxKind.expense, label: Text('Pengeluaran')),
              ButtonSegment(value: TxKind.income, label: Text('Pemasukan')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.text,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Nominal',
              hintText: currency == 'IDR' ? '25k, 1,5jt, 25000' : '12.34',
              prefixText: currency == null ? null : '$currency ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Akun', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final a in accounts)
                ChoiceChip(
                  label: Text('${a.name} (${a.currency})'),
                  selected: accountId == a.id,
                  onSelected: (_) => setState(() => _accountId = a.id),
                ),
            ],
          ),
          if (selected != null && balance != null) ...[
            const SizedBox(height: 8),
            BalanceHint(
              label: 'Saldo ${selected.name}',
              balanceMinor: balance,
              currency: selected.currency,
              afterMinor: after,
            ),
          ],
          const SizedBox(height: 24),
          Text('Kategori', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in visibleCategories)
                ChoiceChip(
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (sel) =>
                      setState(() => _categoryId = sel ? c.id : null),
                ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(DateFormat('EEEE, d MMMM y', 'id_ID').format(_date)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : () => _save(accountId, currency),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
