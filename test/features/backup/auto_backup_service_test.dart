import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/backup/data/auto_backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_file_gateway.dart';
import 'package:personal_finance_manager/features/backup/data/backup_naming.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

/// Folder palsia di memori: nama file -> isi.
class FakeGateway implements BackupFileGateway {
  final Map<String, String> files = {};
  bool failSave = false;

  @override
  Future<String> saveToFolder({
    required String treeUri,
    required String fileName,
    required String content,
  }) async {
    if (failSave) throw StateError('penyimpanan penuh');
    files[fileName] = content;
    return fileName;
  }

  @override
  Future<List<BackupFileEntry>> listFolder(String treeUri) async => [
        for (final name in files.keys)
          BackupFileEntry(name: name, documentId: name),
      ];

  @override
  Future<void> deleteFromFolder({
    required String treeUri,
    required String documentId,
  }) async {
    files.remove(documentId);
  }

  @override
  Future<String?> pickAndRead() => throw UnimplementedError();

  @override
  Future<void> share({required String fileName, required String content}) =>
      throw UnimplementedError();

  @override
  Future<String?> pickFolder() => throw UnimplementedError();

  @override
  Future<BackupFolderInfo?> describeFolder(String treeUri) =>
      throw UnimplementedError();

  @override
  Future<void> releaseFolder(String treeUri) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeGateway gateway;
  late DateTime now;
  late AutoBackupService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
    gateway = FakeGateway();
    now = DateTime(2026, 10, 12, 9, 30);
    service = AutoBackupService(
      backup: BackupService(db),
      gateway: gateway,
      settings: settings,
      clock: () => now,
    );
    await AccountRepository(db).create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> enable() async {
    await settings.set(autoBackupEnabledKey, '1');
    await settings.set(backupFolderUriKey, 'content://fake/tree');
  }

  test('nonaktif: tidak melakukan apa pun', () async {
    await settings.set(backupFolderUriKey, 'content://fake/tree');
    expect(await service.runIfDue(), isFalse);
    expect(gateway.files, isEmpty);
  });

  test('aktif tapi folder belum dipilih: tidak melakukan apa pun', () async {
    await settings.set(autoBackupEnabledKey, '1');
    expect(await service.runIfDue(), isFalse);
    expect(gateway.files, isEmpty);
  });

  test('pertama kali: menulis file dengan nama otomatis dan mencatat waktu',
      () async {
    await enable();
    expect(await service.runIfDue(), isTrue);

    expect(gateway.files.keys.single, autoBackupFileName(now));
    expect(await settings.get(autoBackupLastKey), now.toIso8601String());
    expect(await settings.get(lastBackupSettingKey), now.toIso8601String());
    expect(await settings.get(autoBackupErrorKey), '');
  });

  test('isi file adalah backup yang sah dan bisa diperiksa', () async {
    await enable();
    await service.runIfDue();
    final content = gateway.files.values.single;
    expect(BackupService(db).inspect(content).count('accounts'), 1);
  });

  test('belum jatuh tempo: tidak menulis lagi', () async {
    await enable();
    await service.runIfDue();
    now = now.add(const Duration(hours: 1));
    expect(await service.runIfDue(), isFalse);
    expect(gateway.files.length, 1);
  });

  test('sudah jatuh tempo: menulis file baru', () async {
    await enable();
    await service.runIfDue();
    now = now.add(const Duration(hours: 21));
    expect(await service.runIfDue(), isTrue);
    expect(gateway.files.length, 2);
  });

  test('gagal menyimpan: tidak melempar, error dicatat, waktu tidak maju',
      () async {
    await enable();
    gateway.failSave = true;
    expect(await service.runIfDue(), isFalse);
    expect(await settings.get(autoBackupErrorKey), contains('penyimpanan penuh'));
    expect(await settings.get(autoBackupLastKey), isNull);

    // Percobaan berikutnya (setelah masalah hilang) langsung jalan dan
    // menghapus catatan error.
    gateway.failSave = false;
    expect(await service.runIfDue(), isTrue);
    expect(await settings.get(autoBackupErrorKey), '');
  });

  test('memangkas file otomatis lama, menyisakan 14 terbaru', () async {
    await enable();
    for (var day = 1; day <= 16; day++) {
      final d = day.toString().padLeft(2, '0');
      gateway.files['pfm-auto-2026-09-$d-0900.json'] = '{}';
    }
    gateway.files['pfm-backup-2026-01-01-0000.json'] = '{}'; // manual
    gateway.files['catatan.txt'] = 'bukan backup';

    expect(await service.runIfDue(), isTrue);

    final autos = gateway.files.keys.where((n) => n.startsWith('pfm-auto-')).toList();
    expect(autos.length, AutoBackupService.keepCount);
    expect(autos, contains(autoBackupFileName(now)));
    expect(autos, isNot(contains('pfm-auto-2026-09-01-0900.json')));
    expect(autos, isNot(contains('pfm-auto-2026-09-03-0900.json')));
    expect(autos, contains('pfm-auto-2026-09-04-0900.json'));

    expect(gateway.files.containsKey('pfm-backup-2026-01-01-0000.json'), isTrue);
    expect(gateway.files.containsKey('catatan.txt'), isTrue);
  });
}
