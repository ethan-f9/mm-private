import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/features/backup/data/auto_backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_file_gateway.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/backup/data/platform_backup_file_gateway.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

export 'package:personal_finance_manager/features/backup/data/platform_backup_file_gateway.dart'
    show backupFileGatewayProvider;

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(
    backup: ref.watch(backupServiceProvider),
    gateway: ref.watch(backupFileGatewayProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

class BackupFolderStatus {
  const BackupFolderStatus({this.uri, this.info});

  /// URI yang tersimpan di pengaturan (null = belum pernah memilih).
  final String? uri;

  /// Info folder kalau masih bisa diakses (null = izin hilang / folder dihapus).
  final BackupFolderInfo? info;

  bool get isSet => uri != null;
  bool get accessible => info != null;
}

final backupFolderProvider = FutureProvider<BackupFolderStatus>((ref) async {
  final uri = await ref.watch(settingsRepositoryProvider).get(backupFolderUriKey);
  if (uri == null || uri.isEmpty) return const BackupFolderStatus();
  try {
    final info = await ref.watch(backupFileGatewayProvider).describeFolder(uri);
    return BackupFolderStatus(uri: uri, info: info);
  } catch (_) {
    return BackupFolderStatus(uri: uri);
  }
});

class AutoBackupStatus {
  const AutoBackupStatus({
    required this.enabled,
    required this.lastAt,
    required this.error,
  });

  final bool enabled;
  final DateTime? lastAt;

  /// Null kalau tidak ada error.
  final String? error;
}

final autoBackupStatusProvider = FutureProvider<AutoBackupStatus>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final lastRaw = await settings.get(autoBackupLastKey);
  final error = await settings.get(autoBackupErrorKey);
  return AutoBackupStatus(
    enabled: await settings.get(autoBackupEnabledKey) == '1',
    lastAt: lastRaw == null ? null : DateTime.tryParse(lastRaw),
    error: (error == null || error.isEmpty) ? null : error,
  );
});
