import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LockAuthStatus { success, cancelled, error }

class LockAuthResult {
  const LockAuthResult(this.status, [this.message]);

  final LockAuthStatus status;
  final String? message;
}

/// "success" | "cancelled" | "error:<kode>:<pesan>" dari sisi native.
LockAuthResult parseLockAuthResult(String? raw) {
  if (raw == 'success') return const LockAuthResult(LockAuthStatus.success);
  if (raw == 'cancelled') return const LockAuthResult(LockAuthStatus.cancelled);
  if (raw != null && raw.startsWith('error:')) {
    final parts = raw.split(':');
    final message = parts.length > 2 ? parts.sublist(2).join(':') : '';
    return LockAuthResult(
      LockAuthStatus.error,
      message.isEmpty ? 'Autentikasi gagal (${parts.length > 1 ? parts[1] : '?'})' : message,
    );
  }
  return const LockAuthResult(LockAuthStatus.error, 'Respons autentikasi tidak dikenal');
}

/// Antarmuka ke Android (MainActivity.kt). Dipisah supaya logika kunci bisa
/// di-test dengan implementasi palsu.
abstract class AppLockPlatform {
  /// Perangkat punya kunci layar (PIN/pola/sandi/biometrik terdaftar).
  Future<bool> isDeviceSecure();

  Future<LockAuthResult> authenticate({required String title, String? subtitle});

  /// FLAG_SECURE: blokir screenshot dan pratinjau di daftar app terbaru.
  Future<void> setSecure(bool enabled);
}

class MethodChannelAppLockPlatform implements AppLockPlatform {
  static const _channel =
      MethodChannel('com.ethanmt.personal_finance_manager/app_lock');

  @override
  Future<bool> isDeviceSecure() async =>
      (await _channel.invokeMethod<bool>('isDeviceSecure')) ?? false;

  @override
  Future<LockAuthResult> authenticate({
    required String title,
    String? subtitle,
  }) async {
    final raw = await _channel.invokeMethod<String>('authenticate', {
      'title': title,
      'subtitle': subtitle,
    });
    return parseLockAuthResult(raw);
  }

  @override
  Future<void> setSecure(bool enabled) =>
      _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
}

final appLockPlatformProvider =
    Provider<AppLockPlatform>((ref) => MethodChannelAppLockPlatform());
