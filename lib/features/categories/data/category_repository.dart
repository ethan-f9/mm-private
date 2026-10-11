import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/db/providers.dart';
import 'package:uuid/uuid.dart';

class DefaultCategory {
  const DefaultCategory(this.id, this.name, this.kind, this.icon);

  /// ID tetap (bukan UUID acak) supaya seed idempotent dan konsisten
  /// antar backup/restore.
  final String id;
  final String name;
  final CategoryKind kind;

  /// Nama ikon; dipetakan ke IconData di layer UI.
  final String icon;
}

const defaultCategories = <DefaultCategory>[
  DefaultCategory('default-expense-makanan', 'Makanan', CategoryKind.expense, 'restaurant'),
  DefaultCategory('default-expense-transport', 'Transport', CategoryKind.expense, 'directions_bus'),
  DefaultCategory('default-expense-belanja', 'Belanja', CategoryKind.expense, 'shopping_bag'),
  DefaultCategory('default-expense-tagihan', 'Tagihan', CategoryKind.expense, 'receipt_long'),
  DefaultCategory('default-expense-hiburan', 'Hiburan', CategoryKind.expense, 'movie'),
  DefaultCategory('default-expense-kesehatan', 'Kesehatan', CategoryKind.expense, 'favorite'),
  DefaultCategory('default-expense-pendidikan', 'Pendidikan', CategoryKind.expense, 'school'),
  DefaultCategory('default-expense-lainnya', 'Lainnya', CategoryKind.expense, 'more_horiz'),
  DefaultCategory('default-income-gaji', 'Gaji', CategoryKind.income, 'payments'),
  DefaultCategory('default-income-bonus', 'Bonus', CategoryKind.income, 'card_giftcard'),
  DefaultCategory('default-income-investasi', 'Investasi', CategoryKind.income, 'trending_up'),
  DefaultCategory('default-income-lainnya', 'Lainnya', CategoryKind.income, 'more_horiz'),
];

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Category>> watchAll({CategoryKind? kind}) {
    final query = _db.select(_db.categories);
    if (kind != null) {
      query.where((c) => c.kind.equalsValue(kind));
    }
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch();
  }

  /// Isi kategori default hanya kalau tabel kosong, jadi kategori yang
  /// sengaja dihapus user tidak muncul lagi.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await (_db.select(_db.categories)..limit(1)).get();
    if (existing.isNotEmpty) return;

    await _db.batch((batch) {
      batch.insertAll(
        _db.categories,
        [
          for (final c in defaultCategories)
            CategoriesCompanion.insert(
              id: c.id,
              name: c.name,
              kind: c.kind,
              icon: Value(c.icon),
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  Future<Category> create({
    required String name,
    required CategoryKind kind,
    String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nama kategori tidak boleh kosong');
    }
    final id = _uuid.v4();
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            kind: kind,
            icon: Value(icon),
          ),
        );
    return (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingle();
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
