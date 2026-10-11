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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Database produksi (file SQLite di storage app).
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'finance_db'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
        // Setiap perubahan skema: naikkan schemaVersion dan tulis onUpgrade
        // eksplisit di sini. Jangan pernah drop-and-recreate data user.
      );
}
