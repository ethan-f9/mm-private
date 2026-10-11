import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/money/amount_input.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

class AddTransferPage extends ConsumerStatefulWidget {
  const AddTransferPage({super.key});

  @override
  ConsumerState<AddTransferPage> createState() => _AddTransferPageState();
}

class _AddTransferPageState extends ConsumerState<AddTransferPage> {
  final _amountFrom = TextEditingController();
  final _amountTo = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  String? _fromId;
  String? _toId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountFrom.dispose();
    _amountTo.dispose();
    _fee.dispose();
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

  Future<void> _save({
    required String? fromId,
    required String? toId,
    required String? fromCurrency,
    required String? toCurrency,
  }) async {
    if (fromId == null || toId == null || fromCurrency == null || toCurrency == null) {
      showSnack(context, 'Pilih akun asal dan tujuan');
      return;
    }

    final fromMinor = parseAmountMinor(_amountFrom.text, fromCurrency);
    if (fromMinor == null) {
      showSnack(context, 'Nominal tidak valid');
      return;
    }

    final sameCurrency = fromCurrency == toCurrency;
    final toMinor =
        sameCurrency ? fromMinor : parseAmountMinor(_amountTo.text, toCurrency);
    if (toMinor == null) {
      showSnack(context, 'Nominal yang diterima tidak valid');
      return;
    }

    var feeMinor = 0;
    final feeText = _fee.text.trim();
    if (feeText.isNotEmpty) {
      final parsedFee = parseAmountMinor(feeText, fromCurrency);
      if (parsedFee == null) {
        showSnack(context, 'Biaya admin tidak valid');
        return;
      }
      feeMinor = parsedFee;
    }

    setState(() => _saving = true);
    try {
      final note = _note.text.trim();
      await ref.read(transactionRepositoryProvider).addTransfer(
            fromAccountId: fromId,
            toAccountId: toId,
            fromAmountMinor: fromMinor,
            toAmountMinor: toMinor,
            feeMinor: feeMinor,
            occurredAt: withCurrentTime(_date),
            note: note.isEmpty ? null : note,
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
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    if (accounts.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transfer')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Transfer butuh minimal dua akun.'),
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

    final fromId = _fromId ?? accounts.first.id;
    final toId = _toId ?? accounts[1].id;
    final fromCurrency =
        accounts.where((a) => a.id == fromId).firstOrNull?.currency;
    final toCurrency = accounts.where((a) => a.id == toId).firstOrNull?.currency;
    final crossCurrency =
        fromCurrency != null && toCurrency != null && fromCurrency != toCurrency;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Dari', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final a in accounts)
                ChoiceChip(
                  label: Text('${a.name} (${a.currency})'),
                  selected: fromId == a.id,
                  onSelected: (_) => setState(() => _fromId = a.id),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Ke', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final a in accounts)
                ChoiceChip(
                  label: Text('${a.name} (${a.currency})'),
                  selected: toId == a.id,
                  onSelected: (_) => setState(() => _toId = a.id),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _amountFrom,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Nominal dikirim',
              prefixText: fromCurrency == null ? null : '$fromCurrency ',
              border: const OutlineInputBorder(),
            ),
          ),
          if (crossCurrency) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _amountTo,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Nominal diterima',
                prefixText: '$toCurrency ',
                helperText: 'Kurs dihitung dari dua nominal ini',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _fee,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Biaya admin (opsional)',
              prefixText: fromCurrency == null ? null : '$fromCurrency ',
              border: const OutlineInputBorder(),
            ),
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
            onPressed: _saving
                ? null
                : () => _save(
                      fromId: fromId,
                      toId: toId,
                      fromCurrency: fromCurrency,
                      toCurrency: toCurrency,
                    ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
