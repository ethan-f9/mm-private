import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:uuid/uuid.dart';

class TemplateRepository {
  TemplateRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<TransactionTemplate>> watchAll() {
    final query = _db.select(_db.transactionTemplates)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<TransactionTemplate> create({
    required String name,
    required TxKind kind,
    String? accountId,
    String? categoryId,
    int? amountMinor,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nama template tidak boleh kosong');
    }
    if (trimmed.length > 40) {
      throw ArgumentError('Nama template maksimal 40 karakter');
    }
    if (amountMinor != null && amountMinor <= 0) {
      throw ArgumentError('Nominal template harus lebih dari 0');
    }

    final id = _uuid.v4();
    await _db.into(_db.transactionTemplates).insert(
          TransactionTemplatesCompanion.insert(
            id: id,
            name: trimmed,
            kind: kind,
            accountId: Value(accountId),
            categoryId: Value(categoryId),
            amountMinor: Value(amountMinor),
            note: Value(note),
          ),
        );
    return (_db.select(_db.transactionTemplates)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> delete(String id) {
    return (_db.delete(_db.transactionTemplates)..where((t) => t.id.equals(id)))
        .go();
  }
}

final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => TemplateRepository(ref.watch(appDatabaseProvider)),
);

final templatesProvider = StreamProvider<List<TransactionTemplate>>(
  (ref) => ref.watch(templateRepositoryProvider).watchAll(),
);
