import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_platform.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_settings.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

const appLockTimeoutOptions = <int>[0, 30, 60, 300];
const defaultAppLockTimeoutSeconds = 60;

String appLockTimeoutLabel(int seconds) {
  switch (seconds) {
    case 0:
      return 'Segera';
    case 30:
      return '30 detik';
    case 60:
      return '1 menit';
    case 300:
      return '5 menit';
  }
  return '$seconds detik';
}

class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.timeoutSeconds = defaultAppLockTimeoutSeconds,
    this.secureScreen = false,
    this.authenticating = false,
    this.message,
  });

  final bool enabled;
  final bool locked;
  final int timeoutSeconds;
  final bool secureScreen;
  final bool authenticating;

  /// Pesan untuk layar kunci (mis. autentikasi gagal).
  final String? message;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    int? timeoutSeconds,
    bool? secureScreen,
    bool? authenticating,
    String? message,
    bool clearMessage = false,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      secureScreen: secureScreen ?? this.secureScreen,
      authenticating: authenticating ?? this.authenticating,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Kunci aplikasi (UI): terkunci saat dibuka dingin dan setelah di latar
/// belakang lebih lama dari batas waktu. Autentikasi memakai biometrik atau
/// kunci layar HP. Ini mencegah akses santai; data di HP belum dienkripsi.
class AppLockController extends Notifier<AppLockState> {
  DateTime? _pausedAt;
  DateTime? _ignoreResumeUntil;

  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);
  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);

  @override
  AppLockState build() => const AppLockState();

  /// Dipanggil sekali di main() sebelum UI muncul. Kalau kunci aktif, app
  /// langsung terkunci.
  Future<void> initialize() async {
    final enabled = await _settings.get(appLockEnabledKey) == '1';
    final timeout =
        int.tryParse(await _settings.get(appLockTimeoutKey) ?? '') ??
            defaultAppLockTimeoutSeconds;
    final secure = await _settings.get(secureScreenKey) == '1';

    state = AppLockState(
      enabled: enabled,
      locked: enabled,
      timeoutSeconds: timeout,
      secureScreen: secure,
    );
    try {
      await _platform.setSecure(secure);
    } catch (_) {
      // Layar aman gagal diterapkan; tidak boleh menghalangi app terbuka.
    }
  }

  void onPaused(DateTime now) {
    if (!state.enabled) return;
    _pausedAt ??= now;
  }

  void onResumed(DateTime now) {
    final pausedAt = _pausedAt;
    _pausedAt = null;

    final ignoreUntil = _ignoreResumeUntil;
    if (ignoreUntil != null) {
      _ignoreResumeUntil = null;
      if (now.isBefore(ignoreUntil)) return;
    }

    if (!state.enabled || state.locked || pausedAt == null) return;
    if (now.difference(pausedAt).inSeconds >= state.timeoutSeconds) {
      state = state.copyWith(locked: true, clearMessage: true);
    }
  }

  /// Dipanggil sebelum membuka aktivitas luar yang sah (pemilih folder, share
  /// sheet) supaya kembali dari sana tidak langsung mengunci. Berlaku sekali
  /// dan kedaluwarsa dalam 2 menit.
  void suspendNextResume(DateTime now) {
    _ignoreResumeUntil = now.add(const Duration(minutes: 2));
  }

  Future<void> unlock() async {
    if (!state.enabled || !state.locked || state.authenticating) return;
    state = state.copyWith(authenticating: true, clearMessage: true);
    try {
      if (!await _platform.isDeviceSecure()) {
        // Tanpa kunci layar HP, kunci aplikasi tidak melindungi apa pun dan
        // tidak ada cara membukanya. Jangan kunci pengguna di luar.
        await _settings.set(appLockEnabledKey, '0');
        state = state.copyWith(
          enabled: false,
          locked: false,
          authenticating: false,
          message: 'Kunci layar HP sudah tidak ada, kunci aplikasi dinonaktifkan.',
        );
        return;
      }

      final result = await _platform.authenticate(
        title: 'Buka kunci',
        subtitle: 'Finance',
      );
      switch (result.status) {
        case LockAuthStatus.success:
          state = state.copyWith(
            locked: false,
            authenticating: false,
            clearMessage: true,
          );
        case LockAuthStatus.cancelled:
          state = state.copyWith(authenticating: false);
        case LockAuthStatus.error:
          state = state.copyWith(
            authenticating: false,
            message: result.message ?? 'Autentikasi gagal',
          );
      }
    } catch (e) {
      state = state.copyWith(authenticating: false, message: 'Autentikasi gagal: $e');
    }
  }

  /// Aktifkan kunci. Mengembalikan pesan error, atau null kalau berhasil.
  /// Pengguna harus lolos autentikasi sekali dulu, supaya tidak mengaktifkan
  /// kunci yang ternyata tidak bisa dibuka.
  Future<String?> enable() async {
    if (state.authenticating) return null;
    state = state.copyWith(authenticating: true);
    try {
      if (!await _platform.isDeviceSecure()) {
        return 'Atur dulu kunci layar HP (PIN, pola, sandi, atau sidik jari) '
            'di pengaturan Android.';
      }
      final result = await _platform.authenticate(
        title: 'Aktifkan kunci aplikasi',
        subtitle: 'Konfirmasi dengan kunci HP-mu',
      );
      if (result.status == LockAuthStatus.cancelled) return 'Dibatalkan';
      if (result.status == LockAuthStatus.error) {
        return result.message ?? 'Autentikasi gagal';
      }
      await _settings.set(appLockEnabledKey, '1');
      state = state.copyWith(enabled: true, locked: false);
      return null;
    } catch (e) {
      return 'Gagal mengaktifkan: $e';
    } finally {
      state = state.copyWith(authenticating: false);
    }
  }

  /// Matikan kunci; wajib autentikasi dulu.
  Future<String?> disable() async {
    if (state.authenticating) return null;
    state = state.copyWith(authenticating: true);
    try {
      final result = await _platform.authenticate(
        title: 'Matikan kunci aplikasi',
        subtitle: 'Konfirmasi dengan kunci HP-mu',
      );
      if (result.status == LockAuthStatus.cancelled) return 'Dibatalkan';
      if (result.status == LockAuthStatus.error) {
        return result.message ?? 'Autentikasi gagal';
      }
      await _settings.set(appLockEnabledKey, '0');
      state = state.copyWith(enabled: false, locked: false);
      return null;
    } catch (e) {
      return 'Gagal mematikan: $e';
    } finally {
      state = state.copyWith(authenticating: false);
    }
  }

  Future<void> setTimeout(int seconds) async {
    await _settings.set(appLockTimeoutKey, seconds.toString());
    state = state.copyWith(timeoutSeconds: seconds);
  }

  Future<String?> setSecureScreen(bool enabled) async {
    try {
      await _platform.setSecure(enabled);
      await _settings.set(secureScreenKey, enabled ? '1' : '0');
      state = state.copyWith(secureScreen: enabled);
      return null;
    } catch (e) {
      return 'Gagal mengubah layar aman: $e';
    }
  }
}

final appLockProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
