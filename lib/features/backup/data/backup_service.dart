import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/features/backup/data/backup_settings.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.schemaVersion,
    required this.counts,
  });

  final DateTime? exportedAt;
  final int schemaVersion;

  /// Jumlah baris per tabel, kunci = nama tabel di file backup.
  final Map<String, int> counts;

  int count(String key) => counts[key] ?? 0;
}

class _TableSpec {
  const _TableSpec({
    required this.key,
    required this.dump,
    required this.prepare,
    required this.clear,
  });

  final String key;
  final Future<List<Map<String, dynamic>>> Function() dump;

  /// Parse baris JSON menjadi objek bertipe TANPA menyentuh database
  /// (lempar kalau rusak), lalu kembalikan fungsi yang memasukkannya.
  final Future<void> Function() Function(List<Map<String, dynamic>> rows) prepare;

  final Future<void> Function() clear;
}

/// Backup dan pemulihan seluruh database sebagai satu file JSON.
///
/// - Ekspor: semua tabel dibaca dalam satu transaksi (snapshot konsisten).
/// - Pemulihan: wipe-and-load. Semua baris diparse DULU; baru kemudian
///   database dikosongkan dan diisi ulang dalam satu transaksi. Kalau ada
///   yang gagal, transaksi di-rollback dan data lama utuh.
/// - Tabel yang tidak ada di file (backup dari skema lebih lama) dianggap kosong.
/// - API key TIDAK ikut (disimpan di Keystore, bukan di database).
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const appId = 'personal_finance_manager';
  static const formatVersion = 1;

  /// Urutan = induk dulu (untuk insert). Hapus memakai urutan terbalik.
  late final List<_TableSpec> _specs = [
    _TableSpec(
      key: 'accounts',
      dump: () async =>
          (await _db.select(_db.accounts).get()).map((r) => r.toJson()).toList(),
      prepare: (rows) {
        final parsed = rows.map(Account.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.accounts, parsed));
      },
      clear: () => _db.delete(_db.accounts).go(),
    ),
    _TableSpec(
      key: 'categories',
      dump: () async => (await _db.select(_db.categories).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(Category.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.categories, parsed));
      },
      clear: () => _db.delete(_db.categories).go(),
    ),
    _TableSpec(
      key: 'assets',
      dump: () async =>
          (await _db.select(_db.assets).get()).map((r) => r.toJson()).toList(),
      prepare: (rows) {
        final parsed = rows.map(Asset.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.assets, parsed));
      },
      clear: () => _db.delete(_db.assets).go(),
    ),
    // Pengaturan berawalan `device.` khusus perangkat ini: tidak diekspor,
    // tidak dihapus, dan tidak ditimpa saat pemulihan.
    _TableSpec(
      key: 'app_settings',
      dump: () async => (await _db.select(_db.appSettings).get())
          .where((r) => !r.key.startsWith(deviceSettingPrefix))
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows
            .map(AppSetting.fromJson)
            .where((r) => !r.key.startsWith(deviceSettingPrefix))
            .toList();
        return () => _db.batch((b) => b.insertAll(_db.appSettings, parsed));
      },
      clear: () => (_db.delete(_db.appSettings)
            ..where((r) => r.key.like('$deviceSettingPrefix%').not()))
          .go(),
    ),
    _TableSpec(
      key: 'allocation_targets',
      dump: () async => (await _db.select(_db.allocationTargets).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(AllocationTarget.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.allocationTargets, parsed));
      },
      clear: () => _db.delete(_db.allocationTargets).go(),
    ),
    _TableSpec(
      key: 'fx_rates',
      dump: () async =>
          (await _db.select(_db.fxRates).get()).map((r) => r.toJson()).toList(),
      prepare: (rows) {
        final parsed = rows.map(FxRate.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.fxRates, parsed));
      },
      clear: () => _db.delete(_db.fxRates).go(),
    ),
    _TableSpec(
      key: 'transactions',
      dump: () async => (await _db.select(_db.transactions).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(TransactionRow.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.transactions, parsed));
      },
      clear: () => _db.delete(_db.transactions).go(),
    ),
    _TableSpec(
      key: 'transfers',
      dump: () async =>
          (await _db.select(_db.transfers).get()).map((r) => r.toJson()).toList(),
      prepare: (rows) {
        final parsed = rows.map(Transfer.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.transfers, parsed));
      },
      clear: () => _db.delete(_db.transfers).go(),
    ),
    _TableSpec(
      key: 'trades',
      dump: () async =>
          (await _db.select(_db.trades).get()).map((r) => r.toJson()).toList(),
      prepare: (rows) {
        final parsed = rows.map(Trade.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.trades, parsed));
      },
      clear: () => _db.delete(_db.trades).go(),
    ),
    _TableSpec(
      key: 'price_snapshots',
      dump: () async => (await _db.select(_db.priceSnapshots).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(PriceSnapshot.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.priceSnapshots, parsed));
      },
      clear: () => _db.delete(_db.priceSnapshots).go(),
    ),
    _TableSpec(
      key: 'net_worth_snapshots',
      dump: () async => (await _db.select(_db.netWorthSnapshots).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(NetWorthSnapshot.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.netWorthSnapshots, parsed));
      },
      clear: () => _db.delete(_db.netWorthSnapshots).go(),
    ),
    _TableSpec(
      key: 'advisor_insights',
      dump: () async => (await _db.select(_db.advisorInsights).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(AdvisorInsight.fromJson).toList();
        return () => _db.batch((b) => b.insertAll(_db.advisorInsights, parsed));
      },
      clear: () => _db.delete(_db.advisorInsights).go(),
    ),
    _TableSpec(
      key: 'transaction_templates',
      dump: () async => (await _db.select(_db.transactionTemplates).get())
          .map((r) => r.toJson())
          .toList(),
      prepare: (rows) {
        final parsed = rows.map(TransactionTemplate.fromJson).toList();
        return () =>
            _db.batch((b) => b.insertAll(_db.transactionTemplates, parsed));
      },
      clear: () => _db.delete(_db.transactionTemplates).go(),
    ),
  ];

  /// Seluruh database sebagai teks JSON.
  Future<String> exportJson({DateTime? now}) async {
    final data = await _db.transaction(() async {
      final result = <String, Object?>{};
      for (final spec in _specs) {
        result[spec.key] = await spec.dump();
      }
      return result;
    });

    return jsonEncode({
      'app': appId,
      'format': formatVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'data': data,
    });
  }

  /// Validasi file dan hitung isinya, TANPA mengubah database.
  /// Lempar [BackupFormatException] kalau file tidak sah.
  BackupSummary inspect(String json) {
    final root = _parseRoot(json);
    final data = root['data'] as Map<String, dynamic>;
    return BackupSummary(
      exportedAt: DateTime.tryParse(root['exportedAt']?.toString() ?? ''),
      schemaVersion: root['schemaVersion'] as int,
      counts: {
        for (final spec in _specs) spec.key: _rowsFor(data, spec.key).length,
      },
    );
  }

  /// Ganti SELURUH isi database dengan isi backup. Atomik.
  Future<BackupSummary> restore(String json) async {
    final summary = inspect(json);
    final root = _parseRoot(json);
    final data = root['data'] as Map<String, dynamic>;

    // Tahap 1: parse semua baris. Kalau ada yang rusak, berhenti di sini
    // sebelum database disentuh.
    final inserts = <Future<void> Function()>[];
    for (final spec in _specs) {
      try {
        inserts.add(spec.prepare(_rowsFor(data, spec.key)));
      } catch (e) {
        throw BackupFormatException('Data "${spec.key}" rusak: $e');
      }
    }

    // Tahap 2: kosongkan lalu isi ulang, satu transaksi.
    await _db.transaction(() async {
      for (final spec in _specs.reversed) {
        await spec.clear();
      }
      for (final insert in inserts) {
        await insert();
      }
    });

    return summary;
  }

  Map<String, dynamic> _parseRoot(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('File bukan JSON yang valid');
    }
    if (root is! Map<String, dynamic>) {
      throw const BackupFormatException('Format backup tidak dikenali');
    }
    if (root['app'] != appId) {
      throw const BackupFormatException('File ini bukan backup aplikasi ini');
    }
    final format = root['format'];
    if (format is! int || format > formatVersion) {
      throw const BackupFormatException(
        'Format backup lebih baru dari aplikasi ini. Perbarui aplikasi dulu.',
      );
    }
    final schema = root['schemaVersion'];
    if (schema is! int || schema > _db.schemaVersion) {
      throw const BackupFormatException(
        'Backup dibuat oleh versi aplikasi yang lebih baru. Perbarui aplikasi dulu.',
      );
    }
    if (root['data'] is! Map) {
      throw const BackupFormatException('Isi backup tidak ditemukan');
    }
    return root;
  }

  List<Map<String, dynamic>> _rowsFor(Map<String, dynamic> data, String key) {
    final raw = data[key];
    if (raw == null) return const [];
    if (raw is! List) {
      throw BackupFormatException('Tabel "$key" rusak');
    }
    final rows = <Map<String, dynamic>>[];
    for (final element in raw) {
      if (element is! Map) {
        throw BackupFormatException('Baris di tabel "$key" rusak');
      }
      rows.add(Map<String, dynamic>.from(element));
    }
    return rows;
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(appDatabaseProvider)),
);

/// Kapan terakhir backup dibuat. Null = belum pernah.
final lastBackupProvider = FutureProvider<DateTime?>((ref) async {
  final raw =
      await ref.watch(settingsRepositoryProvider).get(lastBackupSettingKey);
  return raw == null ? null : DateTime.tryParse(raw);
});
