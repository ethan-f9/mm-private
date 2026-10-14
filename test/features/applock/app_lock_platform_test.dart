import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/features/applock/data/app_lock_platform.dart';

void main() {
  group('parseLockAuthResult', () {
    test('success', () {
      expect(parseLockAuthResult('success').status, LockAuthStatus.success);
    });

    test('cancelled', () {
      expect(parseLockAuthResult('cancelled').status, LockAuthStatus.cancelled);
    });

    test('error membawa pesan dari sisi native', () {
      final r = parseLockAuthResult('error:7:Terlalu banyak percobaan');
      expect(r.status, LockAuthStatus.error);
      expect(r.message, 'Terlalu banyak percobaan');
    });

    test('pesan yang memuat titik dua tidak terpotong', () {
      final r = parseLockAuthResult('error:7:Coba lagi: 30 detik');
      expect(r.message, 'Coba lagi: 30 detik');
    });

    test('error tanpa pesan diberi pesan bawaan dengan kodenya', () {
      final r = parseLockAuthResult('error:9:');
      expect(r.status, LockAuthStatus.error);
      expect(r.message, contains('9'));
    });

    test('null atau tidak dikenal dianggap error, bukan sukses', () {
      expect(parseLockAuthResult(null).status, LockAuthStatus.error);
      expect(parseLockAuthResult('apa saja').status, LockAuthStatus.error);
      expect(parseLockAuthResult('').status, LockAuthStatus.error);
    });
  });
}
