import 'dart:convert';

import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_repository.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_input.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_validator.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';
import 'package:personal_finance_manager/features/transactions/data/transaction_text_parser.dart'
    show extractJsonObject;

class AdvisorException implements Exception {
  const AdvisorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pipeline: metrik (Dart) -> ringkasan agregat -> model AI menarasikan ->
/// validator (angka harus ada di data, tanpa rekomendasi beli/jual) -> simpan.
/// Model TIDAK menghitung apa pun.
class AdvisorService {
  AdvisorService({
    required LlmClient llm,
    required SettingsRepository settings,
    required AdvisorRepository repository,
    DateTime Function()? clock,
  })  : _llm = llm,
        _settings = settings,
        _repository = repository,
        _clock = clock ?? DateTime.now;

  final LlmClient _llm;
  final SettingsRepository _settings;
  final AdvisorRepository _repository;
  final DateTime Function() _clock;

  /// Hash input untuk metrik ini; dipakai UI untuk tahu insight tersimpan
  /// masih sesuai data sekarang.
  static String hashFor(AdvisorMetrics metrics) =>
      inputHash(jsonEncode(buildAdvisorInput(metrics)));

  Future<AdvisorPayload> generate(AdvisorMetrics metrics) async {
    if (!metrics.hasEnoughData) {
      throw AdvisorException(
        'Data belum cukup. Advisor butuh minimal $advisorMinDataDays hari '
        'pencatatan dan satu bulan penuh (sekarang ${metrics.dataSpanDays} hari).',
      );
    }

    final input = buildAdvisorInput(metrics);
    final inputJson = jsonEncode(input);

    final output = await _llm.complete(
      role: AiRole.advisor,
      messages: [
        {'role': 'system', 'content': advisorSystemPrompt},
        {'role': 'user', 'content': 'DATA:\n$inputJson'},
      ],
    );

    final jsonText = extractJsonObject(output);
    if (jsonText == null) {
      throw const AdvisorException('Jawaban AI bukan JSON. Coba lagi.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const AdvisorException('JSON dari AI tidak valid. Coba lagi.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AdvisorException('JSON dari AI bukan objek. Coba lagi.');
    }

    final result = validateInsights(
      decoded['insights'],
      allowedNumberTokens(input),
    );
    if (result.accepted.isEmpty) {
      final reason = result.rejections.isEmpty
          ? 'tidak ada insight'
          : result.rejections.first;
      throw AdvisorException(
        'Semua insight dibuang validator ($reason). Coba lagi atau ganti model.',
      );
    }

    final config = await _settings.loadAiConfig();
    final payload = AdvisorPayload(
      items: result.accepted,
      dropped: result.rejections.length,
      model: config.advisorModel,
    );
    await _repository.save(
      inputHash: inputHash(inputJson),
      payloadJson: jsonEncode(payload.toJson()),
      at: _clock(),
    );
    return payload;
  }
}
