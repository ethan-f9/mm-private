import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/templates/data/template_repository.dart';

void main() {
  late AppDatabase db;
  late TemplateRepository templates;
  late Account cash;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    templates = TemplateRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();
    cash = await AccountRepository(db).create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('buat template lengkap lalu baca kembali', () async {
    final t = await templates.create(
      name: 'Makan siang',
      kind: TxKind.expense,
      accountId: cash.id,
      categoryId: 'default-expense-makanan',
      amountMinor: 25000,
      note: 'kantin',
    );
    expect(t.name, 'Makan siang');
    expect(t.kind, TxKind.expense);
    expect(t.accountId, cash.id);
    expect(t.amountMinor, 25000);
    expect(t.note, 'kantin');
  });

  test('akun, kategori, dan nominal boleh kosong', () async {
    final t = await templates.create(name: 'Bebas', kind: TxKind.income);
    expect(t.accountId, isNull);
    expect(t.categoryId, isNull);
    expect(t.amountMinor, isNull);
  });

  test('daftar terurut berdasarkan nama', () async {
    await templates.create(name: 'Zebra', kind: TxKind.expense);
    await templates.create(name: 'Apel', kind: TxKind.expense);
    final all = await templates.watchAll().first;
    expect(all.map((t) => t.name).toList(), ['Apel', 'Zebra']);
  });

  test('hapus template', () async {
    final t = await templates.create(name: 'Hapus aku', kind: TxKind.expense);
    await templates.delete(t.id);
    expect(await templates.watchAll().first, isEmpty);
  });

  test('validasi nama dan nominal', () {
    expect(
      templates.create(name: '   ', kind: TxKind.expense),
      throwsArgumentError,
    );
    expect(
      templates.create(name: 'x' * 41, kind: TxKind.expense),
      throwsArgumentError,
    );
    expect(
      templates.create(name: 'Nol', kind: TxKind.expense, amountMinor: 0),
      throwsArgumentError,
    );
  });

  test('akun fiktif ditolak oleh foreign key', () {
    expect(
      templates.create(
        name: 'Salah',
        kind: TxKind.expense,
        accountId: 'akun-fiktif',
      ),
      throwsA(anything),
    );
  });
}
