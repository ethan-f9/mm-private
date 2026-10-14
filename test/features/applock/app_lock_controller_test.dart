import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_controller.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_platform.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_settings.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

class FakePlatform implements AppLockPlatform {
  bool secure = true;
  bool failSetSecure = false;
  bool? lastSecure;
  int authCalls = 0;
  final titles = <String>[];
  LockAuthResult nextResult = const LockAuthResult(LockAuthStatus.success);
  Completer<LockAuthResult>? hold;

  @override
  Future<bool> isDeviceSecure() async => secure;

  @override
  Future<LockAuthResult> authenticate({required String title, String? subtitle}) {
    authCalls++;
    titles.add(title);
    final completer = hold;
    if (completer != null) return completer.future;
    return Future.value(nextResult);
  }

  @override
  Future<void> setSecure(bool enabled) async {
    if (failSetSecure) throw StateError('tidak didukung');
    lastSecure = enabled;
  }
}

void main() {
  late AppDatabase db;
  late FakePlatform platform;
  late ProviderContainer container;
  late SettingsRepository settings;

  final t0 = DateTime(2026, 10, 14, 9);

  AppLockController lock() => container.read(appLockProvider.notifier);
  AppLockState state() => container.read(appLockProvider);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    platform = FakePlatform();
    settings = SettingsRepository(db);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appLockPlatformProvider.overrideWithValue(platform),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// App dengan kunci aktif dan tidak sedang terkunci.
  Future<void> enabledAndUnlocked() async {
    await lock().initialize();
    expect(await lock().enable(), isNull);
    expect(state().enabled, isTrue);
    expect(state().locked, isFalse);
  }

  group('initialize', () {
    test('kunci nonaktif: tidak terkunci, default 1 menit', () async {
      await lock().initialize();
      expect(state().enabled, isFalse);
      expect(state().locked, isFalse);
      expect(state().timeoutSeconds, 60);
      expect(platform.lastSecure, isFalse);
    });

    test('kunci aktif tersimpan: app langsung terkunci, pengaturan dimuat', () async {
      await settings.set(appLockEnabledKey, '1');
      await settings.set(appLockTimeoutKey, '300');
      await settings.set(secureScreenKey, '1');
      await lock().initialize();
      expect(state().enabled, isTrue);
      expect(state().locked, isTrue);
      expect(state().timeoutSeconds, 300);
      expect(state().secureScreen, isTrue);
      expect(platform.lastSecure, isTrue);
    });

    test('layar aman gagal diterapkan: tidak menghalangi', () async {
      platform.failSetSecure = true;
      await lock().initialize();
      expect(state().locked, isFalse);
    });
  });

  group('enable', () {
    test('HP tanpa kunci layar: ditolak dengan petunjuk, tanpa meminta autentikasi',
        () async {
      platform.secure = false;
      final error = await lock().enable();
      expect(error, contains('kunci layar'));
      expect(state().enabled, isFalse);
      expect(platform.authCalls, 0);
      expect(await settings.get(appLockEnabledKey), isNull);
    });

    test('dibatalkan: tetap nonaktif', () async {
      platform.nextResult = const LockAuthResult(LockAuthStatus.cancelled);
      expect(await lock().enable(), 'Dibatalkan');
      expect(state().enabled, isFalse);
      expect(await settings.get(appLockEnabledKey), isNull);
    });

    test('gagal: pesan error diteruskan', () async {
      platform.nextResult = const LockAuthResult(LockAuthStatus.error, 'sensor mati');
      expect(await lock().enable(), 'sensor mati');
      expect(state().enabled, isFalse);
    });

    test('berhasil: aktif, tersimpan, tidak langsung terkunci', () async {
      expect(await lock().enable(), isNull);
      expect(state().enabled, isTrue);
      expect(state().locked, isFalse);
      expect(state().authenticating, isFalse);
      expect(await settings.get(appLockEnabledKey), '1');
    });
  });

  group('kunci otomatis setelah di latar belakang', () {
    test('kembali sebelum batas waktu: tidak terkunci', () async {
      await enabledAndUnlocked(); // batas 60 detik
      lock().onPaused(t0);
      lock().onResumed(t0.add(const Duration(seconds: 30)));
      expect(state().locked, isFalse);
    });

    test('kembali setelah batas waktu: terkunci', () async {
      await enabledAndUnlocked();
      lock().onPaused(t0);
      lock().onResumed(t0.add(const Duration(seconds: 61)));
      expect(state().locked, isTrue);
    });

    test('tepat di batas waktu: terkunci', () async {
      await enabledAndUnlocked();
      lock().onPaused(t0);
      lock().onResumed(t0.add(const Duration(seconds: 60)));
      expect(state().locked, isTrue);
    });

    test('batas "Segera": terkunci setiap kembali', () async {
      await enabledAndUnlocked();
      await lock().setTimeout(0);
      lock().onPaused(t0);
      lock().onResumed(t0.add(const Duration(seconds: 1)));
      expect(state().locked, isTrue);
    });

    test('kunci nonaktif: tidak pernah terkunci', () async {
      await lock().initialize();
      lock().onPaused(t0);
      lock().onResumed(t0.add(const Duration(hours: 5)));
      expect(state().locked, isFalse);
    });

    test('resume tanpa pause sebelumnya tidak mengunci', () async {
      await enabledAndUnlocked();
      lock().onResumed(t0.add(const Duration(hours: 5)));
      expect(state().locked, isFalse);
    });

    test('beberapa pause berturut-turut memakai waktu pause pertama', () async {
      await enabledAndUnlocked();
      lock().onPaused(t0);
      lock().onPaused(t0.add(const Duration(seconds: 50)));
      lock().onResumed(t0.add(const Duration(seconds: 70)));
      expect(state().locked, isTrue);
    });
  });

  group('suspendNextResume (aktivitas luar yang sah)', () {
    test('kembali dari pemilih file tidak mengunci, siklus berikutnya normal',
        () async {
      await enabledAndUnlocked();
      await lock().setTimeout(0);

      lock().onPaused(t0);
      lock().suspendNextResume(t0);
      lock().onResumed(t0.add(const Duration(minutes: 1)));
      expect(state().locked, isFalse);

      lock().onPaused(t0.add(const Duration(minutes: 2)));
      lock().onResumed(t0.add(const Duration(minutes: 3)));
      expect(state().locked, isTrue);
    });

    test('penangguhan kedaluwarsa setelah 2 menit', () async {
      await enabledAndUnlocked();
      lock().onPaused(t0);
      lock().suspendNextResume(t0);
      lock().onResumed(t0.add(const Duration(minutes: 3)));
      expect(state().locked, isTrue);
    });
  });

  group('unlock', () {
    Future<void> locked() async {
      await settings.set(appLockEnabledKey, '1');
      await lock().initialize();
      expect(state().locked, isTrue);
    }

    test('berhasil: terbuka', () async {
      await locked();
      await lock().unlock();
      expect(state().locked, isFalse);
      expect(state().authenticating, isFalse);
      expect(state().message, isNull);
    });

    test('dibatalkan: tetap terkunci, tanpa pesan error', () async {
      await locked();
      platform.nextResult = const LockAuthResult(LockAuthStatus.cancelled);
      await lock().unlock();
      expect(state().locked, isTrue);
      expect(state().authenticating, isFalse);
      expect(state().message, isNull);
    });

    test('gagal: tetap terkunci dengan pesan', () async {
      await locked();
      platform.nextResult = const LockAuthResult(LockAuthStatus.error, 'terlalu banyak percobaan');
      await lock().unlock();
      expect(state().locked, isTrue);
      expect(state().message, 'terlalu banyak percobaan');
    });

    test('dipanggil dua kali bersamaan: hanya satu autentikasi', () async {
      await locked();
      platform.hold = Completer<LockAuthResult>();
      final first = lock().unlock();
      await lock().unlock(); // diabaikan
      expect(platform.authCalls, 1);
      expect(state().authenticating, isTrue);

      platform.hold!.complete(const LockAuthResult(LockAuthStatus.success));
      await first;
      expect(state().locked, isFalse);
    });

    test('kunci layar HP sudah dihapus: kunci app dimatikan, tidak mengunci pengguna di luar',
        () async {
      await locked();
      platform.secure = false;
      await lock().unlock();
      expect(state().enabled, isFalse);
      expect(state().locked, isFalse);
      expect(platform.authCalls, 0);
      expect(await settings.get(appLockEnabledKey), '0');
    });

    test('tidak melakukan apa pun kalau tidak terkunci', () async {
      await lock().initialize();
      await lock().unlock();
      expect(platform.authCalls, 0);
    });
  });

  group('disable', () {
    test('wajib autentikasi; dibatalkan = tetap aktif', () async {
      await enabledAndUnlocked();
      platform.nextResult = const LockAuthResult(LockAuthStatus.cancelled);
      expect(await lock().disable(), 'Dibatalkan');
      expect(state().enabled, isTrue);
      expect(await settings.get(appLockEnabledKey), '1');
    });

    test('berhasil: nonaktif dan tersimpan', () async {
      await enabledAndUnlocked();
      expect(await lock().disable(), isNull);
      expect(state().enabled, isFalse);
      expect(await settings.get(appLockEnabledKey), '0');
    });

    test('judul autentikasi menjelaskan tujuannya', () async {
      await enabledAndUnlocked();
      await lock().disable();
      expect(platform.titles.last, contains('Matikan'));
    });
  });

  group('pengaturan', () {
    test('batas waktu tersimpan', () async {
      await lock().setTimeout(300);
      expect(state().timeoutSeconds, 300);
      expect(await settings.get(appLockTimeoutKey), '300');
    });

    test('layar aman: diterapkan ke platform dan tersimpan', () async {
      expect(await lock().setSecureScreen(true), isNull);
      expect(platform.lastSecure, isTrue);
      expect(state().secureScreen, isTrue);
      expect(await settings.get(secureScreenKey), '1');
    });

    test('layar aman gagal diterapkan: tidak tersimpan, ada pesan', () async {
      platform.failSetSecure = true;
      expect(await lock().setSecureScreen(true), isNotNull);
      expect(state().secureScreen, isFalse);
      expect(await settings.get(secureScreenKey), isNull);
    });
  });

  test('label batas waktu', () {
    expect(appLockTimeoutLabel(0), 'Segera');
    expect(appLockTimeoutLabel(30), '30 detik');
    expect(appLockTimeoutLabel(60), '1 menit');
    expect(appLockTimeoutLabel(300), '5 menit');
    expect(appLockTimeoutLabel(90), '90 detik');
  });
}
