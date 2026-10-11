import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:uuid/uuid.dart';

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  /// Saldo per akun (minor unit, dalam currency akun itu sendiri):
  /// opening balance + transaksi (income - expense) + transfer masuk
  /// - transfer keluar - fee transfer.
  /// Trade investasi ditambahkan di fase 2.
  static const _balanceSql = '''
SELECT a.id AS id,
  a.opening_balance_minor
  + COALESCE((SELECT SUM(CASE t.kind WHEN 'income' THEN t.amount_minor
                                     ELSE -t.amount_minor END)
              FROM transactions t WHERE t.account_id = a.id), 0)
  + COALESCE((SELECT SUM(tr.to_amount_minor)
              FROM transfers tr WHERE tr.to_account_id = a.id), 0)
  - COALESCE((SELECT SUM(tr.from_amount_minor + tr.fee_minor)
              FROM transfers tr WHERE tr.from_account_id = a.id), 0)
  AS balance_minor
FROM accounts a
''';

  Stream<List<Account>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.accounts);
    if (!includeArchived) {
      query.where((a) => a.archived.equals(false));
    }
    query.orderBy([(a) => OrderingTerm.asc(a.name)]);
    return query.watch();
  }

  Future<Account> create({
    required String name,
    required AccountType type,
    required String currency,
    int openingBalanceMinor = 0,
  }) async {
    CurrencyMeta.of(currency); // lempar ArgumentError kalau currency tidak didukung
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nama akun tidak boleh kosong');
    }

    final id = _uuid.v4();
    await _db.into(_db.accounts).insert(
          AccountsCompanion.insert(
            id: id,
            name: trimmed,
            type: type,
            currency: currency,
            openingBalanceMinor: Value(openingBalanceMinor),
          ),
        );
    return (_db.select(_db.accounts)..where((a) => a.id.equals(id))).getSingle();
  }

  Future<void> archive(String id) {
    return (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(archived: Value(true)));
  }

  Selectable<QueryRow> _balanceQuery() {
    return _db.customSelect(
      _balanceSql,
      readsFrom: {_db.accounts, _db.transactions, _db.transfers},
    );
  }

  Map<String, int> _toMap(List<QueryRow> rows) => {
        for (final row in rows)
          row.read<String>('id'): row.read<int>('balance_minor'),
      };

  /// account id -> saldo (minor unit currency akun).
  Future<Map<String, int>> balances() async => _toMap(await _balanceQuery().get());

  Stream<Map<String, int>> watchBalances() => _balanceQuery().watch().map(_toMap);
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(appDatabaseProvider)),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(),
);

final accountBalancesProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);
