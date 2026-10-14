import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/backup/data/backup_service.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';
import 'package:personal_finance_manager/features/templates/data/template_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_repository.dart';

void main() {
  late AppDatabase source;
  late AppDatabase target;
  late BackupService sourceBackup;
  late BackupService targetBackup;

  final day = DateTime(2026, 10, 11, 10);

  Future<void> fill(AppDatabase db) async {
    final accounts = AccountRepository(db);
    final txs = TransactionRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();

    final cash = await accounts.create(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'IDR',
      openingBalanceMinor: 100000,
    );
    final wise = await accounts.create(
      name: 'Wise',
      type: AccountType.foreign,
      currency: 'USD',
    );
    await txs.addTransaction(
      accountId: cash.id,
      kind: TxKind.expense,
      amountMinor: 7000,
      categoryId: 'default-expense-makanan',
      note: 'mie',
      occurredAt: day,
    );
    await txs.addTransfer(
      fromAccountId: cash.id,
      toAccountId: wise.id,
      fromAmountMinor: 16000,
      toAmountMinor: 100,
      feeMinor: 500,
      occurredAt: day,
    );
    await TemplateRepository(db).create(
      name: 'Makan siang',
      kind: TxKind.expense,
      accountId: cash.id,
      amountMinor: 25000,
    );
    await SettingsRepository(db).set('ai.base_url', 'https://example.com/v1');
  }

  setUp(() async {
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());
    sourceBackup = BackupService(source);
    targetBackup = BackupService(target);
    await fill(source);
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test('ekspor menghasilkan JSON bertanda aplikasi, format, dan skema', () async {
    final json = await sourceBackup.exportJson(now: DateTime(2026, 10, 12, 9));
    final root = jsonDecode(json) as Map<String, dynamic>;
    expect(root['app'], BackupService.appId);
    expect(root['format'], BackupService.formatVersion);
    expect(root['schemaVersion'], source.schemaVersion);
    expect(DateTime.parse(root['exportedAt'] as String), DateTime(2026, 10, 12, 9));
    expect((root['data'] as Map).containsKey('accounts'), isTrue);
  });

  test('inspect menghitung isi tanpa mengubah database', () async {
    final json = await sourceBackup.exportJson();
    final summary = targetBackup.inspect(json);
    expect(summary.count('accounts'), 2);
    expect(summary.count('transactions'), 1);
    expect(summary.count('transfers'), 1);
    expect(summary.count('transaction_templates'), 1);
    expect(await target.select(target.accounts).get(), isEmpty);
  });

  test('ekspor lalu pulihkan ke database kosong: semua identik', () async {
    final json = await sourceBackup.exportJson();
    await targetBackup.restore(json);

    expect(
      (await target.select(target.accounts).get()).map((a) => a.id).toSet(),
      (await source.select(source.accounts).get()).map((a) => a.id).toSet(),
    );
    expect(
      await AccountRepository(target).balances(),
      await AccountRepository(source).balances(),
    );
    expect((await target.select(target.transactions).get()).length, 1);
    expect((await target.select(target.transfers).get()).length, 1);
    expect(
      (await target.select(target.categories).get()).length,
      (await source.select(source.categories).get()).length,
    );
    final template = (await target.select(target.transactionTemplates).get()).single;
    expect(template.name, 'Makan siang');
    expect(template.amountMinor, 25000);
    expect(
      await SettingsRepository(target).get('ai.base_url'),
      'https://example.com/v1',
    );
  });

  test('pulihkan mengganti data lama, bukan menambah', () async {
    await AccountRepository(target).create(
      name: 'Akan hilang',
      type: AccountType.cash,
      currency: 'IDR',
    );
    await targetBackup.restore(await sourceBackup.exportJson());

    final names =
        (await target.select(target.accounts).get()).map((a) => a.name).toSet();
    expect(names, {'Cash', 'Wise'});
  });

  test('Decimal (trade) selamat melewati ekspor dan pulihkan', () async {
    final cash = (await source.select(source.accounts).get())
        .firstWhere((a) => a.name == 'Cash');
    await source.into(source.assets).insert(
          AssetsCompanion.insert(
            id: 'asset-btc',
            type: AssetType.crypto,
            symbol: 'BTC',
            name: 'Bitcoin',
            currency: 'IDR',
            priceSource: PriceSource.auto,
          ),
        );
    await source.into(source.trades).insert(
          TradesCompanion.insert(
            id: 'trade-1',
            assetId: 'asset-btc',
            fundingAccountId: Value(cash.id),
            side: TradeSide.buy,
            quantity: Decimal.parse('0.00500000'),
            price: Decimal.parse('1000000000'),
            occurredAt: day,
          ),
        );

    await targetBackup.restore(await sourceBackup.exportJson());

    final trade = (await target.select(target.trades).get()).single;
    expect(trade.quantity, Decimal.parse('0.005'));
    expect(trade.price, Decimal.parse('1000000000'));
    expect(trade.side, TradeSide.buy);
  });

  test('backup dari skema lama (tanpa tabel template) dianggap template kosong',
      () async {
    final root = jsonDecode(await sourceBackup.exportJson()) as Map<String, dynamic>;
    (root['data'] as Map<String, dynamic>).remove('transaction_templates');
    root['schemaVersion'] = 1;

    await targetBackup.restore(jsonEncode(root));
    expect(await target.select(target.accounts).get(), hasLength(2));
    expect(await target.select(target.transactionTemplates).get(), isEmpty);
  });

  group('file tidak sah ditolak', () {
    test('bukan JSON', () {
      expect(
        () => targetBackup.inspect('ini bukan json'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('bukan backup aplikasi ini', () {
      expect(
        () => targetBackup.inspect('{"app":"lain","format":1}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('format lebih baru', () async {
      final root = jsonDecode(await sourceBackup.exportJson()) as Map<String, dynamic>;
      root['format'] = BackupService.formatVersion + 1;
      expect(
        () => targetBackup.inspect(jsonEncode(root)),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('skema lebih baru dari aplikasi', () async {
      final root = jsonDecode(await sourceBackup.exportJson()) as Map<String, dynamic>;
      root['schemaVersion'] = target.schemaVersion + 1;
      expect(
        () => targetBackup.inspect(jsonEncode(root)),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('kegagalan tidak merusak data yang ada', () {
    late String existingId;

    setUp(() async {
      final existing = await AccountRepository(target).create(
        name: 'Data lama',
        type: AccountType.cash,
        currency: 'IDR',
        openingBalanceMinor: 999,
      );
      existingId = existing.id;
    });

    Future<void> expectTargetUntouched() async {
      final accounts = await target.select(target.accounts).get();
      expect(accounts.single.id, existingId);
      expect(accounts.single.openingBalanceMinor, 999);
    }

    test('baris rusak: ditolak sebelum database disentuh', () async {
      final root = jsonDecode(await sourceBackup.exportJson()) as Map<String, dynamic>;
      final accounts = (root['data'] as Map<String, dynamic>)['accounts'] as List;
      (accounts.first as Map<String, dynamic>).remove('name');

      await expectLater(
        targetBackup.restore(jsonEncode(root)),
        throwsA(isA<BackupFormatException>()),
      );
      await expectTargetUntouched();
    });

    test('foreign key putus: transaksi menunjuk akun yang tidak ada -> rollback',
        () async {
      final root = jsonDecode(await sourceBackup.exportJson()) as Map<String, dynamic>;
      (root['data'] as Map<String, dynamic>)['accounts'] = <dynamic>[];

      await expectLater(
        targetBackup.restore(jsonEncode(root)),
        throwsA(anything),
      );
      await expectTargetUntouched();
    });
  });
}
