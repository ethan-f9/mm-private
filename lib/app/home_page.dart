import 'package:flutter/material.dart';

/// Placeholder. Diganti oleh dashboard net worth di fase 1.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net Worth', style: text.labelLarge),
              const SizedBox(height: 8),
              Text('Rp 0', style: text.displaySmall),
              const SizedBox(height: 24),
              Text(
                'Fase 1: akun, transaksi, transfer, backup.',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
