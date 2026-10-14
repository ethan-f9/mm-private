import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_file_gateway.dart';

/// Satu-satunya tempat yang memakai plugin file/share dan channel native.
/// Operasi folder memakai MainActivity.kt (tanpa plugin pihak ketiga).
class PlatformBackupFileGateway implements BackupFileGateway {
  static const _channel =
      MethodChannel('com.ethanmt.personal_finance_manager/backup_storage');

  @override
  Future<String?> pickAndRead() async {
    // Tanpa filter tipe: file dari Drive/Telegram kadang tidak bertipe json.
    final XFile? picked = await openFile();
    if (picked == null) return null;
    return picked.readAsString();
  }

  @override
  Future<void> share({
    required String fileName,
    required String content,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: fileName,
      ),
    );
  }

  @override
  Future<String?> pickFolder() => _channel.invokeMethod<String>('pickFolder');

  @override
  Future<BackupFolderInfo?> describeFolder(String treeUri) async {
    final raw = await _channel.invokeMapMethod<String, String>(
      'describeFolder',
      {'treeUri': treeUri},
    );
    if (raw == null) return null;
    final name = raw['name'];
    final documentId = raw['documentId'];
    if (name == null || documentId == null) return null;
    return BackupFolderInfo(name: name, documentId: documentId);
  }

  @override
  Future<String> saveToFolder({
    required String treeUri,
    required String fileName,
    required String content,
  }) async {
    final saved = await _channel.invokeMethod<String>('writeFile', {
      'treeUri': treeUri,
      'fileName': fileName,
      'content': content,
    });
    return saved ?? fileName;
  }

  @override
  Future<List<BackupFileEntry>> listFolder(String treeUri) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
          'listFiles',
          {'treeUri': treeUri},
        ) ??
        const <dynamic>[];
    final entries = <BackupFileEntry>[];
    for (final item in raw) {
      final map = item as Map;
      entries.add(
        BackupFileEntry(
          name: map['name'] as String,
          documentId: map['documentId'] as String,
        ),
      );
    }
    return entries;
  }

  @override
  Future<void> deleteFromFolder({
    required String treeUri,
    required String documentId,
  }) {
    return _channel.invokeMethod<void>('deleteFile', {
      'treeUri': treeUri,
      'documentId': documentId,
    });
  }

  @override
  Future<void> releaseFolder(String treeUri) {
    return _channel.invokeMethod<void>('releaseFolder', {'treeUri': treeUri});
  }
}

final backupFileGatewayProvider = Provider<BackupFileGateway>(
  (ref) => PlatformBackupFileGateway(),
);
