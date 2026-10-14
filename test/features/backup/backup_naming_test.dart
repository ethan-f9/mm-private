import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/features/backup/data/backup_file_gateway.dart';
import 'package:personal_finance_manager/features/backup/data/backup_naming.dart';

void main() {
  group('nama file', () {
    test('manual', () {
      expect(
        backupFileName(DateTime(2026, 10, 12, 9, 5)),
        'pfm-backup-2026-10-12-0905.json',
      );
    });

    test('otomatis', () {
      expect(
        autoBackupFileName(DateTime(2026, 1, 2, 23, 59)),
        'pfm-auto-2026-01-02-2359.json',
      );
    });

    test('urutan nama = urutan waktu (dipakai untuk memangkas)', () {
      final names = [
        autoBackupFileName(DateTime(2026, 10, 12, 9)),
        autoBackupFileName(DateTime(2026, 9, 30, 23)),
        autoBackupFileName(DateTime(2026, 10, 2, 8)),
      ]..sort();
      expect(names.first, 'pfm-auto-2026-09-30-2300.json');
      expect(names.last, 'pfm-auto-2026-10-12-0900.json');
    });
  });

  group('isAutoBackupDue', () {
    final now = DateTime(2026, 10, 12, 12);

    test('belum pernah jalan', () {
      expect(isAutoBackupDue(null, now), isTrue);
    });

    test('1 jam lalu: belum waktunya', () {
      expect(isAutoBackupDue(now.subtract(const Duration(hours: 1)), now), isFalse);
    });

    test('21 jam lalu: waktunya', () {
      expect(isAutoBackupDue(now.subtract(const Duration(hours: 21)), now), isTrue);
    });

    test('tepat 20 jam: waktunya', () {
      expect(isAutoBackupDue(now.subtract(const Duration(hours: 20)), now), isTrue);
    });

    test('jam perangkat mundur (terakhir di masa depan): waktunya', () {
      expect(isAutoBackupDue(now.add(const Duration(days: 3)), now), isTrue);
    });
  });

  group('folderLabel', () {
    test('penyimpanan internal', () {
      expect(
        folderLabel('primary:Download/Backup Keuangan'),
        'Penyimpanan internal/Download/Backup Keuangan',
      );
    });

    test('akar volume', () {
      expect(folderLabel('primary:'), 'Penyimpanan internal');
    });

    test('kartu SD', () {
      expect(folderLabel('1234-ABCD:Backup'), '1234-ABCD/Backup');
    });

    test('tanpa titik dua', () {
      expect(folderLabel('aneh'), 'aneh');
    });
  });
}
