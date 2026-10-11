import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arsipkan akun?'),
        content: Text(
          '"$name" disembunyikan dari daftar dan dari total net worth. '
          'Riwayat transaksinya tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(accountRepositoryProvider).archive(id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final Map<String, int> balances =
    ref.watch(accountBalancesProvider).valueOrNull ?? const <String, int>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah akun',
            onPressed: () => context.push('/add-account'),
          ),
        ],
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Belum ada akun. Tekan + di kanan atas untuk menambah.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = list[i];
              return ListTile(
                leading: Icon(accountTypeIcon(a.type)),
                title: Text(a.name),
                subtitle: Text('${accountTypeLabel(a.type)} \u2022 ${a.currency}'),
                trailing: AmountText(
                  minor: balances[a.id] ?? a.openingBalanceMinor,
                  currency: a.currency,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onLongPress: () => _confirmArchive(context, ref, a.id, a.name),
              );
            },
          );
        },
      ),
    );
  }
}
