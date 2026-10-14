import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import 'advisor_metrics.dart';
import 'allocation_presets.dart';

const _monthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String idNumber(int n) => NumberFormat.decimalPattern('id_ID').format(n);

String rupiah(int n) => n < 0 ? '-Rp ${idNumber(-n)}' : 'Rp ${idNumber(n)}';

String pctText(double v, {bool signed = false}) {
  final body = v.abs().toStringAsFixed(1).replaceAll('.', ',');
  final sign = v < 0 ? '-' : (signed && v > 0 ? '+' : '');
  return '$sign$body%';
}

String monthLabel(DateTime m) => '${_monthNames[m.month - 1]} ${m.year}';

/// Ringkasan yang dikirim ke model. HANYA agregat: tidak ada transaksi satu
/// per satu, catatan, nama akun, atau nama merchant. Semua angka sudah
/// diformat (Indonesia) supaya model cukup menyalinnya, dan supaya validator
/// bisa memeriksa tiap angka di jawabannya terhadap teks ini.
Map<String, dynamic> buildAdvisorInput(AdvisorMetrics m) {
  final notes = <String>[
    if (!m.hasTargets) 'Target alokasi belum diatur oleh pengguna.',
    if (m.missingFx.isNotEmpty)
      'Sebagian data belum dihitung karena kurs ${m.missingFx.join(', ')} belum tersedia.',
  ];

  return {
    'mataUang': 'IDR',
    'periode': {
      'rentangDataHari': m.dataSpanDays,
      'bulanDihitung': m.months.length,
      'jendelaTrenHari': 30,
      'minimumDataHari': advisorMinDataDays,
    },
    'ringkasan': {
      if (m.avgMonthlyIncomeMinor != null)
        'rataRataPemasukanBulanan': rupiah(m.avgMonthlyIncomeMinor!),
      if (m.avgMonthlyExpenseMinor != null)
        'rataRataPengeluaranBulanan': rupiah(m.avgMonthlyExpenseMinor!),
      if (m.savingsRatePct != null) 'rasioTabungan': pctText(m.savingsRatePct!),
      'kasDanAkun': rupiah(m.cashMinor),
      if (m.runwayMonths != null)
        'runwayBulan': m.runwayMonths!.toStringAsFixed(1).replaceAll('.', ','),
    },
    'bulanan': [
      for (final month in m.months)
        {
          'bulan': monthLabel(month.month),
          'pemasukan': rupiah(month.incomeMinor),
          'pengeluaran': rupiah(month.expenseMinor),
        },
    ],
    'kategoriPengeluaran30Hari': [
      for (final c in m.categoryTrends)
        {
          'kategori': c.name,
          '30HariTerakhir': rupiah(c.last30Minor),
          '30HariSebelumnya': rupiah(c.prev30Minor),
          if (c.changePct != null) 'perubahan': pctText(c.changePct!, signed: true),
        },
    ],
    'alokasi': [
      for (final a in m.allocation)
        {
          'kelas': assetClassLabel(a.classKey),
          if (a.actualPct != null) 'aktual': pctText(a.actualPct!),
          if (a.targetPct != null) 'target': pctText(a.targetPct!),
          if (a.driftPts != null)
            'selisihPoin': pctText(a.driftPts!, signed: true).replaceAll('%', ''),
        },
    ],
    if (notes.isNotEmpty) 'catatan': notes,
  };
}

const advisorSystemPrompt =
    'Kamu analis keuangan pribadi yang tegas dan ringkas. Kamu menerima '
    'ringkasan angka seorang pengguna dalam JSON (DATA). Tulis 3 sampai 5 '
    'insight yang paling penting.\n'
    'ATURAN KERAS:\n'
    '1. Pakai HANYA angka yang tertulis di DATA dan salin persis seperti '
    'tertulis (contoh "Rp 4.250.000", "+32,5%"). Jangan menghitung, '
    'membulatkan, menjumlah, atau menulis angka baru.\n'
    '2. Setiap insight wajib punya "evidence": kutipan angka dari DATA yang '
    'mendukungnya.\n'
    '3. Dilarang merekomendasikan membeli atau menjual instrumen atau aset '
    'tertentu, dan dilarang memprediksi harga atau pasar. Untuk alokasi cukup '
    'katakan porsi suatu kelas aset di atas atau di bawah target.\n'
    '4. Jangan menyebut hal yang tidak ada di DATA.\n'
    '5. Bahasa Indonesia, langsung, tanpa basa-basi.\n'
    'Balas HANYA satu objek JSON tanpa markdown dengan bentuk: '
    '{"insights":[{"severity":"info"|"warning"|"critical","title":"...",'
    '"detail":"...","evidence":["..."]}]}';

final _numberPattern = RegExp(r'\d+(?:[.,]\d+)*');
final _thousandsDots = RegExp(r'^\d{1,3}(\.\d{3})+$');

/// Bentuk baku sebuah angka bergaya Indonesia: "1.250.000" -> "1250000",
/// "32,5" -> "32.5", "08" -> "8". Null kalau tidak bisa dibaca.
String? normalizeNumberToken(String raw) {
  var s = raw;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (_thousandsDots.hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  final value = Decimal.tryParse(s);
  return value?.toString();
}

/// Semua angka yang muncul di [text], dalam bentuk baku.
Set<String> numberTokens(String text) {
  final tokens = <String>{};
  for (final match in _numberPattern.allMatches(text)) {
    final normalized = normalizeNumberToken(match.group(0)!);
    if (normalized != null) tokens.add(normalized);
  }
  return tokens;
}

/// Angka yang boleh muncul di jawaban model = angka di teks JSON inputnya.
Set<String> allowedNumberTokens(Map<String, dynamic> input) =>
    numberTokens(jsonEncode(input));

/// Hash ringan untuk kunci cache (bukan untuk keamanan): sama input = sama hash.
String inputHash(String text) {
  var h = 0x811C9DC5;
  for (final unit in utf8.encode(text)) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return '${h.toRadixString(16).padLeft(8, '0')}-${text.length}';
}
