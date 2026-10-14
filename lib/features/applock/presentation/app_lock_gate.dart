import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_controller.dart';

/// Membungkus seluruh app. Saat terkunci, menutup semua isi dengan layar kunci
/// dan meminta autentikasi. Juga mengatur kapan app perlu dikunci ulang
/// (berdasarkan lama di latar belakang).
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfLocked());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        controller.onPaused(DateTime.now());
      case AppLifecycleState.resumed:
        controller.onResumed(DateTime.now());
        _promptIfLocked();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Saat terkunci, tombol back tidak boleh menutup halaman di baliknya.
  @override
  Future<bool> didPopRoute() async => ref.read(appLockProvider).locked;

  void _promptIfLocked() {
    final state = ref.read(appLockProvider);
    if (state.locked && !state.authenticating) {
      unawaited(ref.read(appLockProvider.notifier).unlock());
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));

    ref.listen<bool>(appLockProvider.select((s) => s.locked), (previous, next) {
      if (next && !(previous ?? false)) _promptIfLocked();
    });

    return Stack(
      children: [
        widget.child,
        if (locked) const Positioned.fill(child: _LockScreen()),
      ],
    );
  }
}

class _LockScreen extends ConsumerWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final state = ref.watch(appLockProvider);

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                Text('Terkunci', style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Buka dengan sidik jari atau kunci layar HP.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.message!,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: state.authenticating
                      ? null
                      : () => unawaited(ref.read(appLockProvider.notifier).unlock()),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Buka kunci'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
