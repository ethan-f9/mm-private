/// Antarmuka akses file untuk backup. Tidak memakai plugin apa pun di sini,
/// supaya logika yang memakainya bisa di-test dengan implementasi palsu.
/// Implementasi nyata: platform_backup_file_gateway.dart.

class BackupFolderInfo {
  const BackupFolderInfo({required this.name, required this.documentId});

  /// Nama folder saja, mis. "Backup Keuangan".
  final String name;

  /// Id dokumen SAF, mis. "primary:Download/Backup Keuangan".
  final String documentId;

  String get label => folderLabel(documentId);
}

class BackupFileEntry {
  const BackupFileEntry({required this.name, required this.documentId});

  final String name;
  final String documentId;
}

/// "primary:Download/Backup" -> "Penyimpanan internal/Download/Backup".
String folderLabel(String documentId) {
  final colon = documentId.indexOf(':');
  if (colon == -1) return documentId;
  final volume = documentId.substring(0, colon);
  final path = documentId.substring(colon + 1);
  final volumeLabel = volume == 'primary' ? 'Penyimpanan internal' : volume;
  return path.isEmpty ? volumeLabel : '$volumeLabel/$path';
}

abstract class BackupFileGateway {
  /// Pilih file dari penyimpanan dan kembalikan isinya. Null kalau dibatalkan.
  Future<String?> pickAndRead();

  /// Buka share sheet dengan file berisi [content] (opsi cadangan).
  Future<void> share({required String fileName, required String content});

  /// Pilih folder tujuan; izin disimpan permanen. Mengembalikan URI folder,
  /// atau null kalau dibatalkan.
  Future<String?> pickFolder();

  /// Info folder, atau null kalau izin hilang / folder sudah tidak ada.
  Future<BackupFolderInfo?> describeFolder(String treeUri);

  /// Tulis file baru ke folder. Mengembalikan nama file yang tersimpan
  /// (sistem bisa menambah " (1)" kalau namanya sudah ada). Tidak menimpa.
  Future<String> saveToFolder({
    required String treeUri,
    required String fileName,
    required String content,
  });

  Future<List<BackupFileEntry>> listFolder(String treeUri);

  Future<void> deleteFromFolder({
    required String treeUri,
    required String documentId,
  });

  /// Lepas izin folder lama (batas jumlah izin per app di Android).
  Future<void> releaseFolder(String treeUri);
}
