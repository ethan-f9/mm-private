import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';

import 'converters/decimal_converter.dart';
import 'enums.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Transfers,
    Assets,
    Trades,
    PriceSnapshots,
    FxRates,
    NetWorthSnapshots,
    AllocationTargets,
    AdvisorInsights,
    AppSettings,
    TransactionTemplates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Database produksi (file SQLite di storage app).
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'finance_db'));

  /// Riwayat skema:
  /// 1 = skema awal
  /// 2 = tambah tabel `transaction_templates`
  ///
  /// Setiap perubahan skema: naikkan angka ini, tambah blok `if (from < N)`
  /// di onUpgrade, dan tambah test di test/core/db/migration_test.dart.
  /// Jangan pernah drop-and-recreate data user.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(transactionTemplates);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
