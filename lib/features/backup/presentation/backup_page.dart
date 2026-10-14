import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/backup/data/backup_naming.dart';
import 'package:personal_finance_manager/features/backup/data/backup_providers.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  String _errorText(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return errorMessage(e);
  }

  /// Buka pemilih folder dan simpan pilihannya. Null kalau dibatalkan.
  Future<String?> _chooseFolder() async {
    final gateway = ref.read(backupFileGatewayProvider);
    final settings = ref.read(settingsRepositoryProvider);

    final previous = await settings.get(backupFolderUriKey);
    final uri = await gateway.pickFolder();
    if (uri == null) return null;

    await settings.set(backupFolderUriKey, uri);
    if (previous != null && previous.isNotEmpty && previous != uri) {
      try {
        await gateway.releaseFolder(previous);
      } catch (_) {
        // Izin lama sudah tidak ada; tidak masalah.
      }
    }
    ref.invalidate(backupFolderProvider);
    return uri;
  }

  Future<void> _pickFolderOnly() async {
    setState(() => _busy = true);
    try {
      await _chooseFolder();
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal memilih folder: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportToFolder() async {
    setState(() => _busy = true);
    try {
      final gateway = ref.read(backupFileGatewayProvider);
      final settings = ref.read(settingsRepositoryProvider);

      String? uri = await settings.get(backupFolderUriKey);
      final usable = uri != null &&
          uri.isNotEmpty &&
          await gateway.describeFolder(uri) != null;
      if (!usable) {
        uri = await _chooseFolder();
      }
      if (uri == null) return;

      final now = DateTime.now();
      final json = await ref.read(backupServiceProvider).exportJson(now: now);
      final saved = await gateway.saveToFolder(
        treeUri: uri,
        fileName: backupFileName(now),
        content: json,
      );

      await settings.set(lastBackupSettingKey, now.toIso8601String());
      ref.invalidate(lastBackupProvider);
      if (mounted) showSnack(context, 'Tersimpan: $saved');
    } catch (e) {
      if (mounted) showSnack(context, 'Backup gagal: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final json = await ref.read(backupServiceProvider).exportJson(now: now);
      await ref.read(backupFileGatewayProvider).share(
            fileName: backupFileName(now),
            content: json,
          );
      await ref
          .read(settingsRepositoryProvider)
          .set(lastBackupSettingKey, now.toIso8601String());
      ref.invalidate(lastBackupProvider);
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal membagikan: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAutoBackup(bool enabled) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(autoBackupEnabledKey, enabled ? '1' : '0');
    ref.invalidate(autoBackupStatusProvider);
    if (!enabled) return;

    setState(() => _busy = true);
    try {
      final written = await ref.read(autoBackupServiceProvider).runIfDue();
      ref.invalidate(autoBackupStatusProvider);
      ref.invalidate(lastBackupProvider);
      final error = await settings.get(autoBackupErrorKey);
      if (!mounted) return;
      if (error != null && error.isNotEmpty) {
        showSnack(context, 'Backup otomatis gagal: $error');
      } else if (written) {
        showSnack(context, 'Backup otomatis aktif. File pertama sudah dibuat.');
      } else {
        showSnack(context, 'Backup otomatis aktif.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final content = await ref.read(backupFileGatewayProvider).pickAndRead();
      if (content == null) return;

      final service = ref.read(backupServiceProvider);
      final summary = service.inspect(content);
      if (!mounted) return;

      final exportedAt = summary.exportedAt;
      final when = exportedAt == null
          ? 'tanggal tidak diketahui'
          : DateFormat('d MMM y, HH:mm', 'id_ID').format(exportedAt);

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pulihkan backup?'),
          content: Text(
            'Backup $when berisi:\n'
            '\u2022 ${summary.count('accounts')} akun\n'
            '\u2022 ${summary.count('transactions')} transaksi\n'
            '\u2022 ${summary.count('transfers')} transfer\n'
            '\u2022 ${summary.count('transaction_templates')} template\n\n'
            'SEMUA data di HP ini akan DIGANTI dengan isi backup. '
            'Tindakan ini tidak bisa dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ganti data'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      await service.restore(content);

      // Pengaturan ikut berubah; muat ulang yang dipakai di memori.
      final settings = ref.read(settingsRepositoryProvider);
      final stealth = await settings.get(stealthSettingKey);
      ref.read(stealthModeProvider.notifier).state = stealth == '1';
      ref.invalidate(lastBackupProvider);
      ref.invalidate(aiConfigProvider);

      if (mounted) {
        showSnack(
          context,
          'Pemulihan selesai. API key perlu diisi ulang bila belum ada.',
        );
      }
    } on BackupFormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Pemulihan gagal: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _folderText(BackupFolderStatus status) {
    if (!status.isSet) return 'Belum dipilih';
    final info = status.info;
    if (info == null) return 'Folder tidak bisa diakses. Pilih ulang.';
    return info.label;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dateTime = DateFormat('EEEE, d MMM y, HH:mm', 'id_ID');

    final folder = ref.watch(backupFolderProvider);
    final auto = ref.watch(autoBackupStatusProvider);
    final last = ref.watch(lastBackupProvider);

    final folderStatus = folder.valueOrNull;
    final folderUsable = folderStatus != null && folderStatus.accessible;

    final lastText = last.when(
      loading: () => '...',
      error: (_, __) => '-',
      data: (d) => d == null ? 'Belum pernah' : dateTime.format(d),
    );

    final autoStatus = auto.valueOrNull;
    final autoEnabled = autoStatus?.enabled ?? false;
    final autoLines = <String>[
      'Disimpan saat app dibuka, paling sering sekali per hari. '
          'Menyimpan ${14} file otomatis terakhir; backup manual tidak pernah dihapus.',
      if (autoStatus?.lastAt != null)
        'Terakhir otomatis: ${dateTime.format(autoStatus!.lastAt!)}',
      if (autoStatus?.error != null) 'Gagal terakhir kali: ${autoStatus!.error}',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Backup dan pemulihan')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Data keuanganmu hanya tersimpan di HP ini. Kalau app di-uninstall '
            'atau HP hilang, datanya ikut hilang. File backup yang disimpan di '
            'HP melindungi dari uninstall, tapi tidak dari HP hilang: sinkronkan '
            'foldernya ke Google Drive atau Syncthing.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('Folder penyimpanan', style: text.labelLarge),
          const SizedBox(height: 4),
          Text(
            folder.when(
              loading: () => '...',
              error: (_, __) => '-',
              data: _folderText,
            ),
            style: text.titleMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFolderOnly,
            icon: const Icon(Icons.folder_open),
            label: Text(
              folderStatus?.isSet == true ? 'Ganti folder' : 'Pilih folder',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Android 11 ke atas tidak mengizinkan memilih folder Download '
            'langsung. Buka Download, ketuk ikon folder baru, buat folder '
            '(mis. "Backup Keuangan"), lalu pilih folder itu.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Terakhir dibackup', style: text.labelLarge),
          const SizedBox(height: 4),
          Text(lastText, style: text.titleMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _exportToFolder,
            icon: const Icon(Icons.save_alt),
            label: Text(
              folderUsable ? 'Backup sekarang' : 'Pilih folder dan backup',
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share),
            label: const Text('Bagikan ke aplikasi lain'),
          ),
          const Divider(height: 40),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Backup otomatis harian'),
            subtitle: Text(
              folderUsable
                  ? autoLines.join('\n')
                  : 'Pilih folder dulu untuk mengaktifkan.',
            ),
            value: autoEnabled && folderUsable,
            onChanged: (_busy || !folderUsable) ? null : _setAutoBackup,
          ),
          const Divider(height: 40),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Pulihkan dari file'),
          ),
          const SizedBox(height: 24),
          Text(
            'File backup berisi semua akun, transaksi, template, dan pengaturan, '
            'tanpa enkripsi. Perlakukan seperti data sensitif. API key AI dan '
            'pengaturan folder tidak ikut di-backup.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
