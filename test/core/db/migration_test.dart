import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/investments/data/asset_repository.dart';
import 'package:personal_finance_manager/features/templates/data/template_repository.dart';

/// Simulasi database lama: buat database terbaru lewat kode, lalu mundurkan
/// skemanya (hapus yang ditambah versi berikutnya) dan set `user_version`.
/// Membuka lagi dengan skema terbaru harus menjalankan onUpgrade.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pfm_migration_');
    file = File('${dir.path}${Platform.pathSeparator}test.db');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // File sementara; Windows kadang masih mengunci sebentar.
    }
  });

  test('upgrade v1 ke terbaru: tabel template dan kolom external_id ditambah, '
      'data utuh', () async {
    final old = AppDatabase(NativeDatabase(file));
    await AccountRepository(old).create(
      name: 'Lama',
      type: AccountType.cash,
      currency: 'IDR',
      openingBalanceMinor: 1234,
    );
    await old.customStatement('DROP TABLE transaction_templates');
    await old.customStatement('ALTER TABLE assets DROP COLUMN external_id');
    await old.customStatement('PRAGMA user_version = 1');
    await old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    final accounts = await upgraded.select(upgraded.accounts).get();
    expect(accounts.single.name, 'Lama');
    expect(accounts.single.openingBalanceMinor, 1234);

    expect(await upgraded.select(upgraded.transactionTemplates).get(), isEmpty);
    final t = await TemplateRepository(upgraded)
        .create(name: 'Setelah upgrade', kind: TxKind.expense);
    expect(t.name, 'Setelah upgrade');

    final asset = await AssetRepository(upgraded).create(
      type: AssetType.crypto,
      symbol: 'BTC',
      name: 'Bitcoin',
      currency: 'IDR',
      externalId: 'bitcoin',
    );
    expect(asset.externalId, 'bitcoin');
    await upgraded.close();
  });

  test('upgrade v2 ke v3: aset lama tetap ada dengan external_id kosong',
      () async {
    final old = AppDatabase(NativeDatabase(file));
    await AssetRepository(old).create(
      type: AssetType.stock,
      symbol: 'BBCA',
      name: 'BCA',
      currency: 'IDR',
    );
    await old.customStatement('ALTER TABLE assets DROP COLUMN external_id');
    await old.customStatement('PRAGMA user_version = 2');
    await old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    final assets = await upgraded.select(upgraded.assets).get();
    expect(assets.single.symbol, 'BBCA');
    expect(assets.single.externalId, isNull);
    await upgraded.close();
  });
}
