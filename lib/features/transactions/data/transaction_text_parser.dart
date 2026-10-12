import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

/// Hasil tafsiran AI. TIDAK PERNAH disimpan langsung: hanya mengisi form,
/// user yang menekan Simpan. Nominal sengaja tetap berupa teks mentah
/// ("25k"); angkanya ditentukan `IdAmountParser`, bukan LLM.
class ParsedTransaction {
  const ParsedTransaction({
    required this.kind,
    this.accountId,
    this.categoryId,
    this.amountText,
    this.note,
    this.date,
  });

  final TxKind kind;
  final String? accountId;
  final String? categoryId;
  final String? amountText;
  final String? note;
  final DateTime? date;
}

/// Ambil objek JSON pertama dari output model (toleran terhadap pagar
/// markdown atau kalimat pembuka).
String? extractJsonObject(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  return raw.substring(start, end + 1);
}

class TransactionTextParser {
  TransactionTextParser(this._llm);

  final LlmClient _llm;

  Future<ParsedTransaction> parse(
    String text, {
    required List<Account> accounts,
    required List<Category> categories,
    required DateTime today,
  }) async {
    final output = await _llm.complete(
      role: AiRole.parser,
      messages: [
        {
          'role': 'system',
          'content': buildSystemPrompt(accounts, categories, today),
        },
        {'role': 'user', 'content': text},
      ],
    );
    return interpret(output, accounts: accounts, categories: categories);
  }

  static String buildSystemPrompt(
    List<Account> accounts,
    List<Category> categories,
    DateTime today,
  ) {
    final expense = categories
        .where((c) => c.kind == CategoryKind.expense)
        .map((c) => c.name)
        .join(', ');
    final income = categories
        .where((c) => c.kind == CategoryKind.income)
        .map((c) => c.name)
        .join(', ');
    final accountNames = accounts.map((a) => a.name).join(', ');
    final todayText = today.toIso8601String().substring(0, 10);

    return 'Kamu parser catatan keuangan pribadi. Ubah kalimat user menjadi '
        'satu transaksi.\n'
        'Balas HANYA satu objek JSON, tanpa teks lain dan tanpa markdown, '
        'dengan kunci:\n'
        '{"kind":"expense" atau "income",'
        '"amount":"nominal PERSIS seperti ditulis user, contoh 25k atau 1,5jt",'
        '"account":"nama akun dari daftar, atau null",'
        '"category":"nama kategori dari daftar, atau null",'
        '"note":"catatan singkat, atau null",'
        '"date":"YYYY-MM-DD, atau null"}\n'
        'Aturan: jangan menghitung atau mengubah nominal, salin apa adanya. '
        'Jangan mengarang akun atau kategori di luar daftar, pakai null. '
        'Tanggal relatif (kemarin, Senin lalu) dihitung dari hari ini: '
        '$todayText.\n'
        'Daftar akun: $accountNames\n'
        'Kategori pengeluaran: $expense\n'
        'Kategori pemasukan: $income';
  }

  /// Fungsi murni (tanpa jaringan) supaya bisa di-unit-test.
  static ParsedTransaction interpret(
    String output, {
    required List<Account> accounts,
    required List<Category> categories,
  }) {
    final jsonText = extractJsonObject(output);
    if (jsonText == null) {
      throw const FormatException('Respons AI bukan JSON');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const FormatException('JSON dari AI tidak valid');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON dari AI bukan objek');
    }

    final TxKind kind;
    switch (_asText(decoded['kind'])?.toLowerCase()) {
      case 'income':
        kind = TxKind.income;
      case 'expense':
        kind = TxKind.expense;
      default:
        throw const FormatException('Jenis transaksi tidak dikenali');
    }

    return ParsedTransaction(
      kind: kind,
      accountId: _matchAccount(_asText(decoded['account']), accounts),
      categoryId: _matchCategory(_asText(decoded['category']), kind, categories),
      amountText: _asText(decoded['amount']),
      note: _asText(decoded['note']),
      date: _parseDate(_asText(decoded['date'])),
    );
  }

  static String? _asText(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static String? _matchAccount(String? name, List<Account> accounts) {
    if (name == null) return null;
    final query = name.toLowerCase();
    for (final a in accounts) {
      if (a.name.toLowerCase() == query) return a.id;
    }
    for (final a in accounts) {
      final candidate = a.name.toLowerCase();
      if (candidate.contains(query) || query.contains(candidate)) return a.id;
    }
    return null;
  }

  static String? _matchCategory(
    String? name,
    TxKind kind,
    List<Category> categories,
  ) {
    if (name == null) return null;
    final query = name.toLowerCase();
    for (final c in categories) {
      if (c.kind.name == kind.name && c.name.toLowerCase() == query) {
        return c.id;
      }
    }
    return null;
  }

  static DateTime? _parseDate(String? text) {
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

final transactionTextParserProvider = Provider<TransactionTextParser>(
  (ref) => TransactionTextParser(ref.watch(llmClientProvider)),
);
