/// Pengaturan khusus perangkat ini. Awalan `device.` artinya: TIDAK ikut
/// diekspor ke file backup dan TIDAK ditimpa saat pemulihan (alamat folder
/// di HP lama tidak berlaku di HP baru).
const deviceSettingPrefix = 'device.';

const backupFolderUriKey = 'device.backup_folder_uri';

/// Kapan terakhir file backup dibuat (manual maupun otomatis).
const lastBackupSettingKey = 'device.backup_last_at';

const autoBackupEnabledKey = 'device.auto_backup_enabled';
const autoBackupLastKey = 'device.auto_backup_last_at';

/// Pesan error backup otomatis terakhir; kosong kalau terakhir berhasil.
const autoBackupErrorKey = 'device.auto_backup_error';
