import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_input.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_validator.dart';

import 'advisor_test_support.dart';

void main() {
  group('format angka Indonesia', () {
    test('rupiah', () {
      expect(rupiah(1250000), 'Rp 1.250.000');
      expect(rupiah(0), 'Rp 0');
      expect(rupiah(-5000), '-Rp 5.000');
    });

    test('persen', () {
      expect(pctText(32.46), '32,5%');
      expect(pctText(50, signed: true), '+50,0%');
      expect(pctText(-12.34, signed: true), '-12,3%');
      expect(pctText(0, signed: true), '0,0%');
    });

    test('nama bulan', () {
      expect(monthLabel(DateTime(2026, 8)), 'Agustus 2026');
      expect(monthLabel(DateTime(2027, 1)), 'Januari 2027');
    });
  });

  group('normalizeNumberToken / numberTokens', () {
    test('ribuan titik dan desimal koma', () {
      expect(normalizeNumberToken('1.250.000'), '1250000');
      expect(normalizeNumberToken('32,5'), '32.5');
      expect(normalizeNumberToken('1.250.000,50'), '1250000.5');
    });

    test('nol di depan dan desimal titik', () {
      expect(normalizeNumberToken('08'), '8');
      expect(normalizeNumberToken('4.25'), '4.25');
    });

    test('mengekstrak semua angka dari teks', () {
      expect(
        numberTokens('Makanan Rp 1.500.000 naik +50,0% selama 30 hari'),
        containsAll(['1500000', '30']),
      );
      expect(numberTokens('tanpa angka'), isEmpty);
    });
  });

  test('inputHash: stabil, dan berbeda untuk isi berbeda', () {
    expect(inputHash('abc'), inputHash('abc'));
    expect(inputHash('abc'), isNot(inputHash('abd')));
    expect(inputHash('abc'), matches(RegExp(r'^[0-9a-f]{8}-3$')));
  });

  group('buildAdvisorInput', () {
    test('hanya agregat: tidak memuat catatan atau nama akun', () async {
      final db = newDb();
      final metrics = await scenarioMetrics(db);
      final json = jsonEncode(buildAdvisorInput(metrics));
      await db.close();

      expect(json, isNot(contains('rahasia-merchant')));
      expect(json, isNot(contains('Cash'))); // nama akun
      expect(json, contains('Makanan')); // nama kategori ikut
    });

    test('memuat angka hasil hitung Dart dalam format terbaca', () async {
      final db = newDb();
      final metrics = await scenarioMetrics(db);
      final input = buildAdvisorInput(metrics);
      await db.close();

      final summary = input['ringkasan'] as Map<String, dynamic>;
      expect(summary['rataRataPengeluaranBulanan'], 'Rp 5.000.000');
      expect(summary['rataRataPemasukanBulanan'], 'Rp 8.000.000');
      expect(summary['rasioTabungan'], '37,5%');
      expect(summary['runwayBulan'], '3,0');

      final tokens = allowedNumberTokens(input);
      expect(tokens, containsAll(['5000000', '8000000', '37.5', '1500000']));
    });

    test('catatan menyebut target belum diatur', () async {
      final db = newDb();
      final metrics = await scenarioMetrics(db);
      final input = buildAdvisorInput(metrics);
      await db.close();
      expect((input['catatan'] as List).join(' '), contains('Target alokasi'));
    });
  });

  group('validateInsights', () {
    late Set<String> allowed;

    setUp(() async {
      final db = newDb();
      final metrics = await scenarioMetrics(db);
      allowed = allowedNumberTokens(buildAdvisorInput(metrics));
      await db.close();
    });

    Map<String, dynamic> good({String severity = 'warning'}) => {
          'severity': severity,
          'title': 'Pengeluaran Makanan naik',
          'detail': 'Makanan naik +50,0% dibanding 30 hari sebelumnya.',
          'evidence': ['Makanan Rp 1.500.000 vs Rp 1.000.000 (+50,0%)'],
        };

    test('insight yang sesuai data diterima', () {
      final r = validateInsights([good()], allowed);
      expect(r.accepted.length, 1);
      expect(r.rejections, isEmpty);
      expect(r.accepted.single.severity, InsightSeverity.warning);
    });

    test('angka di luar data ditolak', () {
      final bad = good()..['detail'] = 'Makanan naik 77% dibanding sebelumnya.';
      final r = validateInsights([bad], allowed);
      expect(r.accepted, isEmpty);
      expect(r.rejections.single, contains('77'));
    });

    test('evidence kosong atau tanpa angka ditolak', () {
      expect(
        validateInsights([good()..['evidence'] = <String>[]], allowed).accepted,
        isEmpty,
      );
      expect(
        validateInsights([good()..['evidence'] = ['naik banyak']], allowed).accepted,
        isEmpty,
      );
      expect(
        validateInsights([good()..remove('evidence')], allowed).accepted,
        isEmpty,
      );
    });

    test('saran beli/jual dan prediksi ditolak', () {
      for (final phrase in [
        'Sebaiknya jual saham sekarang.',
        'Pertimbangkan beli emas.',
        'Harga akan naik bulan depan.',
        'Ini prediksi saya.',
        'Target harga Rp 1.500.000.',
      ]) {
        final bad = good()..['detail'] = phrase;
        expect(
          validateInsights([bad], allowed).accepted,
          isEmpty,
          reason: phrase,
        );
      }
    });

    test('kata "pembelian" tidak dianggap saran beli', () {
      final ok = good()..['detail'] = 'Pembelian rutin: Makanan Rp 1.500.000.';
      expect(validateInsights([ok], allowed).accepted.length, 1);
    });

    test('bentuk rusak ditolak, daftar bukan list ditolak', () {
      expect(validateInsights(['teks'], allowed).accepted, isEmpty);
      expect(validateInsights([good()..['title'] = ' '], allowed).accepted, isEmpty);
      final r = validateInsights('bukan list', allowed);
      expect(r.accepted, isEmpty);
      expect(r.rejections, isNotEmpty);
    });

    test('severity tidak dikenal menjadi info', () {
      final r = validateInsights([good(severity: 'dahsyat')], allowed);
      expect(r.accepted.single.severity, InsightSeverity.info);
    });

    test('maksimal 5 insight diterima', () {
      final r = validateInsights([for (var i = 0; i < 8; i++) good()], allowed);
      expect(r.accepted.length, 5);
    });

    test('sebagian diterima, sebagian dibuang dengan alasan', () {
      final bad = good()..['detail'] = 'Naik 99%.';
      final r = validateInsights([good(), bad], allowed);
      expect(r.accepted.length, 1);
      expect(r.rejections.length, 1);
    });
  });

  test('AdvisorItem dan AdvisorPayload bisa disimpan dan dibaca kembali', () {
    const payload = AdvisorPayload(
      items: [
        AdvisorItem(
          severity: InsightSeverity.critical,
          title: 'T',
          detail: 'D 5',
          evidence: ['E 5'],
        ),
      ],
      dropped: 2,
      model: 'm',
    );
    final back = AdvisorPayload.fromJson(
      jsonDecode(jsonEncode(payload.toJson())) as Map<String, dynamic>,
    );
    expect(back.dropped, 2);
    expect(back.model, 'm');
    expect(back.items.single.severity, InsightSeverity.critical);
    expect(back.items.single.evidence, ['E 5']);
  });
}
