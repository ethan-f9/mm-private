import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_finance_manager/features/accounts/presentation/accounts_page.dart';
import 'package:personal_finance_manager/features/investments/presentation/portfolio_page.dart';
import 'package:personal_finance_manager/features/networth/presentation/dashboard_page.dart';
import 'package:personal_finance_manager/features/transactions/presentation/ledger_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = <Widget>[
    DashboardPage(),
    LedgerPage(),
    PortfolioPage(),
    AccountsPage(),
  ];

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Catat transaksi'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/add-transaction');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer antar akun'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/add-transfer');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Ringkasan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transaksi',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_up),
            selectedIcon: Icon(Icons.trending_up),
            label: 'Investasi',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Akun',
          ),
        ],
      ),
    );
  }
}
