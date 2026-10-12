import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/templates/data/template_repository.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_providers.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TransactionTemplate template,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus template?'),
        content: Text('"${template.name}" akan dihapus.'),
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
    if (ok == true) {
      await ref.read(templateRepositoryProvider).delete(template.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    final List<Account> accounts =
        ref.watch(allAccountsProvider).valueOrNull ?? const [];
    final List<Category> categories =
        ref.watch(categoriesProvider).valueOrNull ?? const [];
    final accountById = {for (final a in accounts) a.id: a};
    final categoryNames = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Template transaksi')),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Belum ada template. Buat dari layar Tambah Transaksi '
                  'lewat tombol "Simpan sebagai template".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = list[i];
              final account = t.accountId == null ? null : accountById[t.accountId];
              final categoryName =
                  t.categoryId == null ? null : categoryNames[t.categoryId];
              final amount = t.amountMinor;
              final parts = <String>[
                t.kind == TxKind.income ? 'Pemasukan' : 'Pengeluaran',
                if (account != null) account.name,
                if (categoryName != null) categoryName,
              ];

              return ListTile(
                title: Text(t.name),
                subtitle: Text(parts.join(' \u2022 ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (amount != null && account != null)
                      AmountText(minor: amount, currency: account.currency),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Hapus',
                      onPressed: () => _confirmDelete(context, ref, t),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
