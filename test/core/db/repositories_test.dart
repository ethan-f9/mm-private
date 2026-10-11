import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late CategoryRepository categories;
  late TransactionRepository txs;

  final day = DateTime(2026, 10, 1);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    categories = CategoryRepository(db);
    txs = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('saldo akun', () {
    test('hanya opening balance', () async {
      final a = await accounts.create(
        name: 'BCA',
        type: AccountType.bank,
        currency: 'IDR',
        openingBalanceMinor: 1000000,
      );
      expect((await accounts.balances())[a.id], 1000000);
    });

    test('akun tanpa data tetap muncul dengan saldo 0', () async {
      final a = await accounts.create(
        name: 'Dompet',
        type: AccountType.cash,
        currency: 'IDR',
      );
      expect((await accounts.balances())[a.id], 0);
    });

    test('income menambah, expense mengurangi', () async {
      final a = await accounts.create(
        name: 'BCA',
        type: AccountType.bank,
        currency: 'IDR',
        openingBalanceMinor: 1000000,
      );
      await txs.addTransaction(
        accountId: a.id,
        kind: TxKind.income,
        amountMinor: 5000000,
        occurredAt: day,
      );
      await txs.addTransaction(
        accountId: a.id,
        kind: TxKind.expense,
        amountMinor: 25000,
        occurredAt: day,
      );
      expect((await accounts.balances())[a.id], 1000000 + 5000000 - 25000);
    });

    test('transfer satu currency: asal berkurang amount+fee, tujuan bertambah',
        () async {
      final bca = await accounts.create(
        name: 'BCA',
        type: AccountType.bank,
        currency: 'IDR',
        openingBalanceMinor: 1000000,
      );
      final gopay = await accounts.create(
        name: 'GoPay',
        type: AccountType.ewallet,
        currency: 'IDR',
      );
      await txs.addTransfer(
        fromAccountId: bca.id,
        toAccountId: gopay.id,
        fromAmountMinor: 200000,
        toAmountMinor: 200000,
        feeMinor: 2500,
        occurredAt: day,
      );
      final b = await accounts.balances();
      expect(b[bca.id], 1000000 - 200000 - 2500);
      expect(b[gopay.id], 200000);
    });

    test('transfer lintas currency memakai nominal masing-masing', () async {
      final idr = await accounts.create(
        name: 'BCA',
        type: AccountType.bank,
        currency: 'IDR',
        openingBalanceMinor: 5000000,
      );
      final usd = await accounts.create(
        name: 'Wise USD',
        type: AccountType.foreign,
        currency: 'USD',
      );
      // Rp 1.600.000 -> USD 100,00 (10000 minor unit)
      await txs.addTransfer(
        fromAccountId: idr.id,
        toAccountId: usd.id,
        fromAmountMinor: 1600000,
        toAmountMinor: 10000,
        occurredAt: day,
      );
      final b = await accounts.balances();
      expect(b[idr.id], 5000000 - 1600000);
      expect(b[usd.id], 10000);
    });

    test('transfer tidak mengubah total income/expense transaksi', () async {
      final a = await accounts.create(
        name: 'A',
        type: AccountType.bank,
        currency: 'IDR',
        openingBalanceMinor: 100000,
      );
      final b = await accounts.create(
        name: 'B',
        type: AccountType.bank,
        currency: 'IDR',
      );
      await txs.addTransfer(
        fromAccountId: a.id,
        toAccountId: b.id,
        fromAmountMinor: 40000,
        toAmountMinor: 40000,
        occurredAt: day,
      );
      final rows =
          await txs.watchBetween(DateTime(2026), DateTime(2027)).first;
      expect(rows, isEmpty);
    });

    test('akun diarsipkan: hilang dari daftar, saldo tetap dihitung', () async {
      final a = await accounts.create(
        name: 'Lama',
        type: AccountType.cash,
        currency: 'IDR',
        openingBalanceMinor: 500,
      );
      await accounts.archive(a.id);
      expect(await accounts.watchAll().first, isEmpty);
      expect((await accounts.watchAll(includeArchived: true).first).length, 1);
      expect((await accounts.balances())[a.id], 500);
    });
  });

  group('validasi transaksi', () {
    late Account idrAccount;

    setUp(() async {
      idrAccount = await accounts.create(
        name: 'BCA',
        type: AccountType.bank,
        currency: 'IDR',
      );
      await categories.seedDefaultsIfEmpty();
    });

    test('currency transaksi mengikuti akun', () async {
      await txs.addTransaction(
        accountId: idrAccount.id,
        kind: TxKind.expense,
        amountMinor: 1000,
        occurredAt: day,
      );
      final rows =
          await txs.watchBetween(DateTime(2026), DateTime(2027)).first;
      expect(rows.single.currency, 'IDR');
    });

    test('nominal nol atau negatif ditolak', () {
      expect(
        txs.addTransaction(
          accountId: idrAccount.id,
          kind: TxKind.expense,
          amountMinor: 0,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
      expect(
        txs.addTransaction(
          accountId: idrAccount.id,
          kind: TxKind.expense,
          amountMinor: -5,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
    });

    test('akun tidak ada ditolak', () {
      expect(
        txs.addTransaction(
          accountId: 'tidak-ada',
          kind: TxKind.expense,
          amountMinor: 1000,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
    });

    test('kategori income tidak boleh dipakai di expense', () {
      final income =
          defaultCategories.firstWhere((c) => c.kind == CategoryKind.income);
      expect(
        txs.addTransaction(
          accountId: idrAccount.id,
          kind: TxKind.expense,
          amountMinor: 1000,
          categoryId: income.id,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
    });

    test('transfer ke akun yang sama ditolak', () {
      expect(
        txs.addTransfer(
          fromAccountId: idrAccount.id,
          toAccountId: idrAccount.id,
          fromAmountMinor: 100,
          toAmountMinor: 100,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
    });

    test('transfer satu currency dengan nominal beda ditolak', () async {
      final other = await accounts.create(
        name: 'GoPay',
        type: AccountType.ewallet,
        currency: 'IDR',
      );
      expect(
        txs.addTransfer(
          fromAccountId: idrAccount.id,
          toAccountId: other.id,
          fromAmountMinor: 100000,
          toAmountMinor: 99000,
          occurredAt: day,
        ),
        throwsArgumentError,
      );
    });

    test('currency tidak didukung ditolak saat buat akun', () {
      expect(
        accounts.create(name: 'X', type: AccountType.cash, currency: 'XXX'),
        throwsArgumentError,
      );
    });
  });

  group('kategori', () {
    test('seed default terisi dan idempotent', () async {
      await categories.seedDefaultsIfEmpty();
      await categories.seedDefaultsIfEmpty();
      final all = await categories.watchAll().first;
      expect(all.length, defaultCategories.length);
    });

    test('filter berdasarkan kind', () async {
      await categories.seedDefaultsIfEmpty();
      final expenses = await categories.watchAll(kind: CategoryKind.expense).first;
      expect(expenses, isNotEmpty);
      expect(expenses.every((c) => c.kind == CategoryKind.expense), isTrue);
    });
  });

  group('integritas database', () {
    test('foreign key aktif: transaksi ke akun fiktif ditolak DB', () async {
      expect(
        db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                id: 'x',
                accountId: 'akun-fiktif',
                kind: TxKind.expense,
                amountMinor: 1,
                currency: 'IDR',
                occurredAt: day,
              ),
            ),
        throwsA(anything),
      );
    });
  });
}
