import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

enum AiRole { parser, advisor }

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// Client chat completions gaya OpenAI. URL, model, dan API key dibaca saat
/// dipanggil, jadi perubahan di Pengaturan langsung berlaku.
///
/// Aturan pemakaian (lihat docs/ARCHITECTURE.md):
/// - LLM tidak menghitung. Kirim agregat yang sudah dihitung Dart.
/// - Parameter khusus provider (response_format, reasoning_effort) lewat
///   [extraBody], tidak ditanam di sini karena tidak semua provider mendukung.
/// - Output selalu divalidasi di Dart sebelum dipakai.
class LlmClient {
  LlmClient({
    required Future<AiConfig> Function() readConfig,
    required Future<String?> Function() readApiKey,
    http.Client? httpClient,
  })  : _readConfig = readConfig,
        _readApiKey = readApiKey,
        _http = httpClient ?? http.Client();

  final Future<AiConfig> Function() _readConfig;
  final Future<String?> Function() _readApiKey;
  final http.Client _http;

  /// Mengembalikan isi `message.content` dari choice pertama.
  Future<String> complete({
    required AiRole role,
    required List<Map<String, String>> messages,
    double temperature = 0.2,
    Map<String, dynamic>? extraBody,
  }) async {
    final config = await _readConfig();
    final key = await _readApiKey();
    if (key == null || key.isEmpty) {
      throw LlmException('API key AI belum diatur di Pengaturan.');
    }

    final model =
        role == AiRole.parser ? config.parserModel : config.advisorModel;
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      ...?extraBody,
    };

    final res = await _http
        .post(
          config.chatCompletionsUri,
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    final responseText = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      final shown = responseText.length > 300
          ? responseText.substring(0, 300)
          : responseText;
      throw LlmException(shown, statusCode: res.statusCode);
    }

    final decoded = jsonDecode(responseText);
    if (decoded is! Map<String, dynamic>) {
      throw LlmException('Respons tidak dikenali');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmException('Respons AI tidak berisi jawaban');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw LlmException('Respons AI kosong');
    }
    return content;
  }
}
