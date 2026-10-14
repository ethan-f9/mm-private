import 'package:personal_finance_manager/features/backup/data/backup_file_gateway.dart';
import 'package:personal_finance_manager/features/backup/data/backup_naming.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

/// Backup otomatis: dipanggil saat app dibuka atau kembali ke depan. Menulis
/// satu file ke folder pilihan paling sering sekali per ~20 jam, lalu
/// memangkas file otomatis lama (backup manual tidak pernah dihapus).
///
/// Ini BUKAN penjadwal latar belakang: kalau app tidak dibuka, tidak ada
/// backup. Untuk pemakaian harian itu cukup.
class AutoBackupService {
  AutoBackupService({
    required BackupService backup,
    required BackupFileGateway gateway,
    required SettingsRepository settings,
    DateTime Function()? clock,
  })  : _backup = backup,
        _gateway = gateway,
        _settings = settings,
        _clock = clock ?? DateTime.now;

  /// Jumlah file otomatis terbaru yang disimpan.
  static const keepCount = 14;

  final BackupService _backup;
  final BackupFileGateway _gateway;
  final SettingsRepository _settings;
  final DateTime Function() _clock;

  bool _running = false;

  /// True kalau sebuah file backup baru berhasil ditulis. Tidak pernah
  /// melempar: kegagalan dicatat di [autoBackupErrorKey].
  Future<bool> runIfDue() async {
    if (_running) return false;
    _running = true;
    try {
      if (await _settings.get(autoBackupEnabledKey) != '1') return false;
      final treeUri = await _settings.get(backupFolderUriKey);
      if (treeUri == null || treeUri.isEmpty) return false;

      final now = _clock();
      final lastRaw = await _settings.get(autoBackupLastKey);
      final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
      if (!isAutoBackupDue(last, now)) return false;

      final json = await _backup.exportJson(now: now);
      await _gateway.saveToFolder(
        treeUri: treeUri,
        fileName: autoBackupFileName(now),
        content: json,
      );

      await _settings.set(autoBackupLastKey, now.toIso8601String());
      await _settings.set(lastBackupSettingKey, now.toIso8601String());
      await _settings.set(autoBackupErrorKey, '');

      await _prune(treeUri);
      return true;
    } catch (e) {
      await _recordError(e);
      return false;
    } finally {
      _running = false;
    }
  }

  Future<void> _prune(String treeUri) async {
    try {
      final autos = (await _gateway.listFolder(treeUri))
          .where(
            (f) => f.name.startsWith(autoBackupPrefix) && f.name.endsWith('.json'),
          )
          .toList()
        // Nama memuat cap waktu, jadi urutan nama = urutan waktu.
        ..sort((a, b) => b.name.compareTo(a.name));

      for (final old in autos.skip(keepCount)) {
        await _gateway.deleteFromFolder(
          treeUri: treeUri,
          documentId: old.documentId,
        );
      }
    } catch (_) {
      // Pemangkasan gagal tidak membatalkan backup yang sudah tersimpan.
    }
  }

  Future<void> _recordError(Object error) async {
    try {
      await _settings.set(autoBackupErrorKey, error.toString());
    } catch (_) {
      // Tidak ada yang bisa dilakukan lagi.
    }
  }
}
