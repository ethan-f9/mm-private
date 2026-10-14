import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/advisor/domain/allocation_presets.dart';

class AllocationRepository {
  AllocationRepository(this._db);

  final AppDatabase _db;

  /// kelas aset -> target dalam basis points. Kosong = belum diatur.
  Stream<Map<String, int>> watch() {
    return _db.select(_db.allocationTargets).watch().map(
          (rows) => {for (final r in rows) r.assetClass: r.targetBps},
        );
  }

  /// Total harus tepat 100% (10000 bps). Kelas yang tidak disebut dianggap 0.
  Future<void> save(Map<String, int> targetBps) async {
    for (final key in targetBps.keys) {
      if (!assetClassKeys.contains(key)) {
        throw ArgumentError('Kelas aset tidak dikenal: $key');
      }
    }
    final full = {for (final k in assetClassKeys) k: targetBps[k] ?? 0};
    if (full.values.any((v) => v < 0 || v > 10000)) {
      throw ArgumentError('Tiap target harus antara 0% dan 100%');
    }
    final total = full.values.fold<int>(0, (s, v) => s + v);
    if (total != 10000) {
      throw ArgumentError(
        'Total target harus 100% (sekarang ${(total / 100).toStringAsFixed(1)}%)',
      );
    }

    await _db.transaction(() async {
      await _db.delete(_db.allocationTargets).go();
      await _db.batch((b) {
        b.insertAll(_db.allocationTargets, [
          for (final e in full.entries)
            AllocationTargetsCompanion.insert(
              assetClass: e.key,
              targetBps: e.value,
            ),
        ]);
      });
    });
  }
}
