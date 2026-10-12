import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_filter.dart';
import 'package:personal_finance_manager/features/transactions/domain/ledger_item.dart';

void main() {
  late AppDatabase db;
  late List<LedgerItem> items;
  late Map<String, String> categoryNames;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final accounts = AccountRepository(db);
    final categories = CategoryRepository(db);
    final txs = TransactionRepository(db);

    final a = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
    );
    final b = await accounts.create(
      name: 'GoPay',
      type: AccountType.ewallet,
      currency: 'IDR',
    );
    await categories.seedDefaultsIfEmpty();

    await txs.addTransaction(
      accountId: a.id,
      kind: TxKind.expense,
      amountMinor: 7000,
      categoryId: 'default-expense-makanan',
      note: 'mie',
      occurredAt: DateTime(2026, 10, 11, 10),
    );
    await txs.addTransaction(
      accountId: a.id,
      kind: TxKind.expense,
      amountMinor: 15000,
      categoryId: 'default-expense-transport',
      occurredAt: DateTime(2026, 10, 11, 9),
    );
    await txs.addTransaction(
      accountId: a.id,
      kind: TxKind.income,
      amountMinor: 25000,
      categoryId: 'default-income-gaji',
      note: 'Gaji',
      occurredAt: DateTime(2026, 10, 12, 8),
    );
    await txs.addTransfer(
      fromAccountId: a.id,
      toAccountId: b.id,
      fromAmountMinor: 5000,
      toAmountMinor: 5000,
      note: 'tf',
      occurredAt: DateTime(2026, 10, 11, 12),
    );

    final from = DateTime(2026);
    final to = DateTime(2027);
    final txRows = await txs.watchBetween(from, to).first;
    final trRows = await txs.watchTransfersBetween(from, to).first;
    items = <LedgerItem>[
      for (final t in txRows) TransactionItem(t),
      for (final t in trRows) TransferItem(t),
    ]..sort((x, y) => y.occurredAt.compareTo(x.occurredAt));

    final allCategories = await categories.watchAll().first;
    categoryNames = {for (final c in allCategories) c.id: c.name};
  });

  tearDown(() async {
    await db.close();
  });

  List<LedgerItem> filtered(LedgerFilter f) =>
      applyLedgerFilter(items, f, categoryNames: categoryNames);

  group('groupByDay', () {
    test('dikelompokkan per hari, terbaru dulu', () {
      final groups = groupByDay(items);
      expect(groups.length, 2);
      expect(groups[0].day, DateTime(2026, 10, 12));
      expect(groups[0].items.length, 1);
      expect(groups[1].day, DateTime(2026, 10, 11));
      expect(groups[1].items.length, 3);
    });

    test('urutan dalam sehari: jam terbaru dulu', () {
      final day = groupByDay(items)[1];
      expect(day.items[0], isA<TransferItem>()); // 12:00
      expect((day.items[1] as TransactionItem).row.note, 'mie'); // 10:00
      expect((day.items[2] as TransactionItem).row.note, isNull); // 09:00
    });

    test('daftar kosong menghasilkan grup kosong', () {
      expect(groupByDay(const []), isEmpty);
    });
  });

  group('dailyNetMinor', () {
    test('pemasukan dikurangi pengeluaran, transfer diabaikan', () {
      final groups = groupByDay(items);
      expect(dailyNetMinor(groups[0], 'IDR'), 25000);
      expect(dailyNetMinor(groups[1], 'IDR'), -22000);
    });

    test('currency tanpa transaksi mengembalikan null', () {
      expect(dailyNetMinor(groupByDay(items)[0], 'USD'), isNull);
    });
  });

  group('applyLedgerFilter', () {
    test('semua', () {
      expect(filtered(const LedgerFilter()).length, 4);
    });

    test('pengeluaran saja', () {
      final r = filtered(const LedgerFilter(kind: LedgerKind.expense));
      expect(r.length, 2);
      expect(r.every((i) => i is TransactionItem), isTrue);
    });

    test('pemasukan saja', () {
      expect(filtered(const LedgerFilter(kind: LedgerKind.income)).length, 1);
    });

    test('transfer saja', () {
      final r = filtered(const LedgerFilter(kind: LedgerKind.transfer));
      expect(r.length, 1);
      expect(r.single, isA<TransferItem>());
    });

    test('cari di catatan', () {
      expect(filtered(const LedgerFilter(query: 'mie')).length, 1);
    });

    test('cari di nama kategori kalau catatan kosong', () {
      final r = filtered(const LedgerFilter(query: 'transport'));
      expect(r.length, 1);
      expect((r.single as TransactionItem).row.amountMinor, 15000);
    });

    test('pencarian tidak peduli huruf besar/kecil', () {
      expect(filtered(const LedgerFilter(query: 'GAJI')).length, 1);
      expect(filtered(const LedgerFilter(query: '  mIe  ')).length, 1);
    });

    test('cari di catatan transfer', () {
      final r = filtered(const LedgerFilter(query: 'tf'));
      expect(r.single, isA<TransferItem>());
    });

    test('tanpa hasil', () {
      expect(filtered(const LedgerFilter(query: 'xyz')), isEmpty);
    });

    test('jenis dan pencarian digabung', () {
      expect(
        filtered(const LedgerFilter(kind: LedgerKind.transfer, query: 'mie')),
        isEmpty,
      );
      expect(
        filtered(const LedgerFilter(kind: LedgerKind.expense, query: 'mie'))
            .length,
        1,
      );
    });
  });

  group('effectiveRange', () {
    final month = DateTime(2026, 10);

    test('default: bulan aktif', () {
      expect(
        effectiveRange(const LedgerFilter(), month),
        LedgerRange(DateTime(2026, 10), DateTime(2026, 11)),
      );
    });

    test('mencari: semua tanggal', () {
      expect(
        effectiveRange(const LedgerFilter(query: 'mie'), month),
        LedgerRange.all,
      );
    });

    test('rentang pilihan user menang atas pencarian', () {
      final picked = LedgerRange(DateTime(2026, 9, 1), DateTime(2026, 9, 15));
      expect(
        effectiveRange(LedgerFilter(query: 'mie', range: picked), month),
        picked,
      );
    });

    test('copyWith clearRange menghapus rentang', () {
      final f = LedgerFilter(
        range: LedgerRange(DateTime(2026, 9, 1), DateTime(2026, 9, 15)),
      );
      expect(f.copyWith(clearRange: true).range, isNull);
    });
  });
}
