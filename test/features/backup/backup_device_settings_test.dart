import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase source;
  late AppDatabase target;

  setUp(() {
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test('pengaturan device.* tidak ikut diekspor', () async {
    final s = SettingsRepository(source);
    await s.set('ai.base_url', 'https://example.com/v1');
    await s.set(backupFolderUriKey, 'content://folder-hp-lama');
    await s.set(autoBackupEnabledKey, '1');

    final json = await BackupService(source).exportJson();
    final root = jsonDecode(json) as Map<String, dynamic>;
    final rows = (root['data'] as Map<String, dynamic>)['app_settings'] as List;
    final keys = rows.map((r) => (r as Map<String, dynamic>)['key']).toList();

    expect(keys, contains('ai.base_url'));
    expect(keys.any((k) => (k as String).startsWith(deviceSettingPrefix)), isFalse);
  });

  test('pemulihan mempertahankan pengaturan device.* milik HP ini', () async {
    await SettingsRepository(source).set('ai.base_url', 'https://dari-backup/v1');
    final json = await BackupService(source).exportJson();

    final t = SettingsRepository(target);
    await t.set(backupFolderUriKey, 'content://folder-hp-ini');
    await t.set(autoBackupEnabledKey, '1');
    await t.set('ai.base_url', 'https://lama/v1');

    await BackupService(target).restore(json);

    expect(await t.get(backupFolderUriKey), 'content://folder-hp-ini');
    expect(await t.get(autoBackupEnabledKey), '1');
    expect(await t.get('ai.base_url'), 'https://dari-backup/v1');
  });

  test('baris device.* di dalam file backup (jika ada) diabaikan saat pemulihan',
      () async {
    final json = await BackupService(source).exportJson();
    final root = jsonDecode(json) as Map<String, dynamic>;
    (root['data'] as Map<String, dynamic>)['app_settings'] = [
      {'key': backupFolderUriKey, 'value': 'content://dari-file'},
    ];

    final t = SettingsRepository(target);
    await t.set(backupFolderUriKey, 'content://folder-hp-ini');
    await BackupService(target).restore(jsonEncode(root));

    expect(await t.get(backupFolderUriKey), 'content://folder-hp-ini');
  });
}
