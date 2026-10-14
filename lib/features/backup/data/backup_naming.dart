const manualBackupPrefix = 'pfm-backup-';
const autoBackupPrefix = 'pfm-auto-';

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}';

/// Contoh: pfm-backup-2026-10-12-0930.json (dibuat dari tombol Ekspor).
String backupFileName(DateTime t) => '$manualBackupPrefix${_stamp(t)}.json';

/// Contoh: pfm-auto-2026-10-12-0930.json. Hanya file berawalan ini yang
/// dipangkas oleh backup otomatis; backup manual tidak pernah dihapus.
String autoBackupFileName(DateTime t) => '$autoBackupPrefix${_stamp(t)}.json';

/// Backup otomatis jatuh tempo kalau belum pernah jalan, sudah lewat
/// [interval], atau jam perangkat mundur (terakhir di masa depan).
bool isAutoBackupDue(
  DateTime? last,
  DateTime now, {
  Duration interval = const Duration(hours: 20),
}) {
  if (last == null) return true;
  if (last.isAfter(now)) return true;
  return now.difference(last) >= interval;
}
