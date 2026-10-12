import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/accounts/data/account_repository.dart';
import 'package:personal_finance_manager/features/templates/data/template_repository.dart';

void main() {
  test('upgrade v1 ke v2 menambah tabel template tanpa menghapus data', () async {
    final dir = Directory.systemTemp.createTempSync('pfm_migration_');
    final file = File('${dir.path}${Platform.pathSeparator}test.db');

    try {
      // Simulasi database lama (v1): data ada, tabel template belum ada.
      final old = AppDatabase(NativeDatabase(file));
      await AccountRepository(old).create(
        name: 'Lama',
        type: AccountType.cash,
        currency: 'IDR',
        openingBalanceMinor: 1234,
      );
      await old.customStatement('DROP TABLE transaction_templates');
      await old.customStatement('PRAGMA user_version = 1');
      await old.close();

      // Buka lagi dengan skema terbaru: onUpgrade harus berjalan.
      final upgraded = AppDatabase(NativeDatabase(file));
      final accounts = await upgraded.select(upgraded.accounts).get();
      expect(accounts.single.name, 'Lama');
      expect(accounts.single.openingBalanceMinor, 1234);

      expect(await upgraded.select(upgraded.transactionTemplates).get(), isEmpty);
      final t = await TemplateRepository(upgraded)
          .create(name: 'Setelah upgrade', kind: TxKind.expense);
      expect(t.name, 'Setelah upgrade');
      await upgraded.close();
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // File sementara; Windows kadang masih mengunci sebentar.
      }
    }
  });
}
