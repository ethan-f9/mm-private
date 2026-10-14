import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/features/applock/presentation/app_lock_gate.dart';
import 'package:personal_finance_manager/features/backup/data/backup_providers.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/market/data/market_refresh_service.dart';

import 'router.dart';
import 'theme.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_onForeground()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_onForeground());
  }

  /// Saat app dibuka/kembali ke depan: backup otomatis dan pembaruan data
  /// pasar (masing-masing punya batas frekuensi sendiri; tidak pernah melempar).
  Future<void> _onForeground() async {
    await _autoBackup();
    final market = await ref.read(marketRefreshServiceProvider).runIfStale();
    if (market != null && mounted) {
      ref.invalidate(marketLastRefreshProvider);
    }
  }

  Future<void> _autoBackup() async {
    final written = await ref.read(autoBackupServiceProvider).runIfDue();
    if (written && mounted) {
      ref.invalidate(lastBackupProvider);
      ref.invalidate(autoBackupStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
