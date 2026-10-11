import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:uuid/uuid.dart';

/// Semua validasi invarian ada di sini, bukan di UI:
/// - nominal selalu > 0 (arah ditentukan `kind`)
/// - currency transaksi SELALU mengikuti akun (tidak bisa mismatch)
/// - kategori harus bertipe sama dengan transaksi
/// - transfer: akun berbeda; satu currency = nominal asal == tujuan
///   (fee dicatat terpisah, dalam currency akun asal)
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Future<String> addTransaction({
    required String accountId,
    required TxKind kind,
    required int amountMinor,
    required DateTime occurredAt,
    String? categoryId,
    String? note,
    TxSource source = TxSource.manual,
  }) async {
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountMinor, 'amountMinor', 'harus lebih dari 0');
    }
    final account = await _requireAccount(accountId);

    if (categoryId != null) {
      final category = await (_db.select(_db.categories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingleOrNull();
      if (category == null) {
        throw ArgumentError('Kategori tidak ditemukan: $categoryId');
      }
      if (category.kind.name != kind.name) {
        throw ArgumentError(
          'Kategori "${category.name}" bertipe ${category.kind.name}, '
          'transaksi bertipe ${kind.name}',
        );
      }
    }

    final id = _uuid.v4();
    await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            accountId: accountId,
            categoryId: Value(categoryId),
            kind: kind,
            amountMinor: amountMinor,
            currency: account.currency,
            note: Value(note),
            occurredAt: occurredAt,
            source: Value(source),
          ),
        );
    return id;
  }

  Future<String> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int fromAmountMinor,
    required int toAmountMinor,
    required DateTime occurredAt,
    int feeMinor = 0,
    String? note,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Akun asal dan tujuan tidak boleh sama');
    }
    if (fromAmountMinor <= 0 || toAmountMinor <= 0) {
      throw ArgumentError('Nominal transfer harus lebih dari 0');
    }
    if (feeMinor < 0) {
      throw ArgumentError.value(feeMinor, 'feeMinor', 'tidak boleh negatif');
    }

    final from = await _requireAccount(fromAccountId);
    final to = await _requireAccount(toAccountId);
    if (from.currency == to.currency && fromAmountMinor != toAmountMinor) {
      throw ArgumentError(
        'Transfer satu currency: nominal asal dan tujuan harus sama '
        '(isi biaya admin di fee)',
      );
    }

    final id = _uuid.v4();
    await _db.into(_db.transfers).insert(
          TransfersCompanion.insert(
            id: id,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            fromAmountMinor: fromAmountMinor,
            toAmountMinor: toAmountMinor,
            feeMinor: Value(feeMinor),
            note: Value(note),
            occurredAt: occurredAt,
          ),
        );
    return id;
  }

  /// Transaksi dalam rentang [from, to), terbaru dulu.
  Stream<List<TransactionRow>> watchBetween(DateTime from, DateTime to) {
    final query = _db.select(_db.transactions)
      ..where(
        (t) =>
            t.occurredAt.isBiggerOrEqualValue(from) &
            t.occurredAt.isSmallerThanValue(to),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch();
  }

  /// Transfer dalam rentang [from, to), terbaru dulu.
  Stream<List<Transfer>> watchTransfersBetween(DateTime from, DateTime to) {
    final query = _db.select(_db.transfers)
      ..where(
        (t) =>
            t.occurredAt.isBiggerOrEqualValue(from) &
            t.occurredAt.isSmallerThanValue(to),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch();
  }

  Future<void> deleteTransfer(String id) {
    return (_db.delete(_db.transfers)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteTransaction(String id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  Future<Account> _requireAccount(String id) async {
    final account = await (_db.select(_db.accounts)
          ..where((a) => a.id.equals(id)))
        .getSingleOrNull();
    if (account == null) {
      throw ArgumentError('Akun tidak ditemukan: $id');
    }
    return account;
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);
