import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/advisor/data/allocation_repository.dart';
import 'package:personal_finance_manager/features/advisor/domain/allocation_presets.dart';

import 'advisor_test_support.dart';

void main() {
  late AppDatabase db;
  late AllocationRepository repo;

  setUp(() {
    db = newDb();
    repo = AllocationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('semua preset berjumlah tepat 100%', () {
    for (final p in allocationPresets) {
      expect(p.bps.values.fold<int>(0, (s, v) => s + v), 10000, reason: p.name);
      expect(p.bps.keys.toSet(), assetClassKeys.toSet(), reason: p.name);
    }
  });

  test('belum diatur: kosong', () async {
    expect(await repo.watch().first, isEmpty);
  });

  test('simpan preset lalu baca kembali', () async {
    final moderat = allocationPresets.firstWhere((p) => p.name == 'Moderat');
    await repo.save(moderat.bps);
    expect(await repo.watch().first, moderat.bps);
  });

  test('menyimpan lagi menimpa, bukan menambah', () async {
    await repo.save(allocationPresets.first.bps);
    final agresif = allocationPresets.firstWhere((p) => p.name == 'Agresif');
    await repo.save(agresif.bps);
    expect(await repo.watch().first, agresif.bps);
    expect((await db.select(db.allocationTargets).get()).length, 5);
  });

  test('kelas yang tidak disebut dianggap 0', () async {
    await repo.save({'cash': 10000});
    final saved = await repo.watch().first;
    expect(saved['cash'], 10000);
    expect(saved['stock'], 0);
  });

  test('total bukan 100% ditolak', () async {
    await expectLater(repo.save({'cash': 5000, 'stock': 4000}), throwsArgumentError);
  });

  test('nilai negatif atau lebih dari 100% ditolak', () async {
    await expectLater(
      repo.save({'cash': -1000, 'stock': 11000}),
      throwsArgumentError,
    );
    await expectLater(repo.save({'cash': 10001}), throwsArgumentError);
  });

  test('kelas tidak dikenal ditolak', () async {
    await expectLater(
      repo.save({'cash': 5000, 'properti': 5000}),
      throwsArgumentError,
    );
  });

  test('gagal menyimpan tidak menghapus target lama', () async {
    await repo.save(allocationPresets.first.bps);
    await expectLater(repo.save({'cash': 1}), throwsArgumentError);
    expect(await repo.watch().first, allocationPresets.first.bps);
  });
}
