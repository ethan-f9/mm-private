import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/amount_input.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';

class AddAccountPage extends ConsumerStatefulWidget {
  const AddAccountPage({super.key});

  @override
  ConsumerState<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends ConsumerState<AddAccountPage> {
  final _name = TextEditingController();
  final _opening = TextEditingController();
  AccountType _type = AccountType.bank;
  String _currency = CurrencyMeta.baseCurrency;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var openingMinor = 0;
    final openingText = _opening.text.trim();
    if (openingText.isNotEmpty) {
      final parsed = parseAmountMinor(openingText, _currency);
      if (parsed == null) {
        showSnack(context, 'Saldo awal tidak valid (contoh: 500k, 1,5jt)');
        return;
      }
      openingMinor = parsed;
    }

    setState(() => _saving = true);
    try {
      await ref.read(accountRepositoryProvider).create(
            name: _name.text,
            type: _type,
            currency: _currency,
            openingBalanceMinor: openingMinor,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Akun')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama akun',
              hintText: 'BCA, GoPay, Dompet',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Tipe', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in AccountType.values)
                ChoiceChip(
                  label: Text(accountTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Currency', style: text.labelLarge),
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
          const SizedBox(height: 24),
          TextField(
            controller: _opening,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Saldo awal (opsional)',
              prefixText: '$_currency ',
              border: const OutlineInputBorder(),
            ),
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
