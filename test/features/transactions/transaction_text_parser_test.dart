import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_text_parser.dart';

void main() {
  late AppDatabase db;
  late Account cash;
  late Account gopay;
  late List<Account> accounts;
  late List<Category> categories;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final accountRepo = AccountRepository(db);
    final categoryRepo = CategoryRepository(db);
    cash = await accountRepo.create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
    );
    gopay = await accountRepo.create(
      name: 'GoPay',
      type: AccountType.ewallet,
      currency: 'IDR',
    );
    await categoryRepo.seedDefaultsIfEmpty();
    accounts = await accountRepo.watchAll().first;
    categories = await categoryRepo.watchAll().first;
  });

  tearDown(() async {
    await db.close();
  });

  ParsedTransaction interpret(String output) => TransactionTextParser.interpret(
        output,
        accounts: accounts,
        categories: categories,
      );

  test('JSON bersih dipetakan ke akun dan kategori', () {
    final r = interpret(
      '{"kind":"expense","amount":"25k","account":"gopay",'
      '"category":"Makanan","note":"nasi padang","date":null}',
    );
    expect(r.kind, TxKind.expense);
    expect(r.accountId, gopay.id);
    expect(r.categoryId, 'default-expense-makanan');
    expect(r.amountText, '25k');
    expect(r.note, 'nasi padang');
    expect(r.date, isNull);
  });

  test('pagar markdown dan kalimat pembuka ditoleransi', () {
    final r = interpret(
      'Tentu, ini hasilnya:\n```json\n'
      '{"kind":"income","amount":"5jt","account":"Cash","category":"Gaji"}\n'
      '```',
    );
    expect(r.kind, TxKind.income);
    expect(r.accountId, cash.id);
    expect(r.categoryId, 'default-income-gaji');
    expect(r.amountText, '5jt');
  });

  test('nominal berupa angka dijadikan teks', () {
    final r = interpret('{"kind":"expense","amount":25000}');
    expect(r.amountText, '25000');
  });

  test('akun dan kategori di luar daftar menjadi null', () {
    final r = interpret(
      '{"kind":"expense","amount":"1k","account":"Dana","category":"Judi"}',
    );
    expect(r.accountId, isNull);
    expect(r.categoryId, isNull);
  });

  test('kategori bertipe lain diabaikan', () {
    final r = interpret(
      '{"kind":"income","amount":"1k","category":"Makanan"}',
    );
    expect(r.categoryId, isNull);
  });

  test('tanggal diparse tanpa jam', () {
    final r = interpret('{"kind":"expense","amount":"1k","date":"2026-10-10"}');
    expect(r.date, DateTime(2026, 10, 10));
  });

  test('string "null" dan kosong dianggap tidak ada', () {
    final r = interpret(
      '{"kind":"expense","amount":"1k","note":"null","account":""}',
    );
    expect(r.note, isNull);
    expect(r.accountId, isNull);
  });

  test('bukan JSON melempar FormatException', () {
    expect(() => interpret('maaf saya tidak mengerti'),
        throwsA(isA<FormatException>()));
  });

  test('JSON rusak melempar FormatException', () {
    expect(() => interpret('{"kind": expense,}'),
        throwsA(isA<FormatException>()));
  });

  test('jenis transaksi tidak dikenal melempar FormatException', () {
    expect(() => interpret('{"kind":"transfer","amount":"1k"}'),
        throwsA(isA<FormatException>()));
  });

  test('prompt memuat daftar akun, kategori, dan tanggal hari ini', () {
    final prompt = TransactionTextParser.buildSystemPrompt(
      accounts,
      categories,
      DateTime(2026, 10, 11),
    );
    expect(prompt, contains('GoPay'));
    expect(prompt, contains('Makanan'));
    expect(prompt, contains('Gaji'));
    expect(prompt, contains('2026-10-11'));
  });
}
