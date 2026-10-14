import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:uuid/uuid.dart';

class AdvisorRepository {
  AdvisorRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  /// Hanya riwayat terbaru ini yang disimpan.
  static const keepCount = 20;

  Future<void> save({
    required String inputHash,
    required String payloadJson,
    required DateTime at,
  }) async {
    await _db.into(_db.advisorInsights).insert(
          AdvisorInsightsCompanion.insert(
            id: _uuid.v4(),
            generatedAt: at,
            inputHash: inputHash,
            payloadJson: payloadJson,
          ),
        );

    final all = await (_db.select(_db.advisorInsights)
          ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)]))
        .get();
    final old = all.skip(keepCount).map((r) => r.id).toList();
    if (old.isNotEmpty) {
      await (_db.delete(_db.advisorInsights)..where((t) => t.id.isIn(old))).go();
    }
  }

  Stream<AdvisorInsight?> watchLatest() {
    final query = _db.select(_db.advisorInsights)
      ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
      ..limit(1);
    return query.watchSingleOrNull();
  }
}
