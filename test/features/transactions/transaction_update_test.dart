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
  late TransactionRepository txs;
  late Account cash;
  late Account bank;
  late String txId;

  final day = DateTime(2026, 10, 11, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    txs = TransactionRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();

    cash = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
      openingBalanceMinor: 100000,
    );
    bank = await accounts.create(
      name: 'BCA',
      type: AccountType.bank,
      currency: 'IDR',
      openingBalanceMinor: 500000,
    );
    txId = await txs.addTransaction(
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 10000,
      categoryId: 'default-expense-makanan',
      note: 'mie',
      occurredAt: day,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<TransactionRow> load() async =>
      (await txs.watchBetween(DateTime(2026), DateTime(2027)).first).single;

  test('ubah nominal menghitung ulang saldo', () async {
    expect((await accounts.balances())[cash.id], 90000);
    await txs.updateTransaction(
      id: txId,
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 25000,
      categoryId: 'default-expense-makanan',
      note: 'mie',
      occurredAt: day,
    );
    expect((await accounts.balances())[cash.id], 75000);
  });

  test('pindah akun memindahkan efek saldo', () async {
    await txs.updateTransaction(
      id: txId,
      accountId: bank.id,
      kind: TxKind.expense,
      amountMinor: 10000,
      occurredAt: day,
    );
    final b = await accounts.balances();
    expect(b[cash.id], 100000);
    expect(b[bank.id], 490000);
  });

  test('ubah jenis ke income membalik arah saldo', () async {
    await txs.updateTransaction(
      id: txId,
      accountId: cash.id,
      kind: TxKind.income,
      amountMinor: 10000,
      categoryId: 'default-income-gaji',
      occurredAt: day,
    );
    expect((await accounts.balances())[cash.id], 110000);
  });

  test('catatan dan kategori bisa dikosongkan', () async {
    await txs.updateTransaction(
      id: txId,
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 10000,
      occurredAt: day,
    );
    final row = await load();
    expect(row.note, isNull);
    expect(row.categoryId, isNull);
  });

  test('sumber transaksi tidak berubah saat diedit', () async {
    final aiId = await txs.addTransaction(
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 1000,
      occurredAt: day,
      source: TxSource.ai,
    );
    await txs.updateTransaction(
      id: aiId,
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 2000,
      occurredAt: day,
    );
    final rows = await txs.watchBetween(DateTime(2026), DateTime(2027)).first;
    final edited = rows.firstWhere((r) => r.id == aiId);
    expect(edited.source, TxSource.ai);
    expect(edited.amountMinor, 2000);
  });

  test('validasi sama dengan tambah: nominal nol ditolak', () {
    expect(
      txs.updateTransaction(
        id: txId,
        accountId: cash.id,
        kind: TxKind.expense,
        amountMinor: 0,
        occurredAt: day,
      ),
      throwsArgumentError,
    );
  });

  test('kategori bertipe lain ditolak', () {
    expect(
      txs.updateTransaction(
        id: txId,
        accountId: cash.id,
        kind: TxKind.expense,
        amountMinor: 1000,
        categoryId: 'default-income-gaji',
        occurredAt: day,
      ),
      throwsArgumentError,
    );
  });

  test('id tidak ada ditolak', () {
    expect(
      txs.updateTransaction(
        id: 'tidak-ada',
        accountId: cash.id,
        kind: TxKind.expense,
        amountMinor: 1000,
        occurredAt: day,
      ),
      throwsArgumentError,
    );
  });
}
