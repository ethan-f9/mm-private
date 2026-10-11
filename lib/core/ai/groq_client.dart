import 'dart:convert';

import 'package:http/http.dart' as http;

class GroqModels {
  GroqModels._();

  static const primary = 'openai/gpt-oss-120b';
  static const light = 'openai/gpt-oss-20b';
}

class GroqException implements Exception {
  GroqException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'GroqException($statusCode): $body';
}

/// Client tipis untuk endpoint chat completions (OpenAI-compatible) milik Groq.
///
/// Aturan pemakaian (lihat docs/ARCHITECTURE.md):
/// - LLM tidak menghitung. Kirim agregat yang sudah dihitung Dart.
/// - Minta output JSON terstruktur, validasi di Dart sebelum dipakai.
/// - Hasil advisor di-cache berdasarkan hash input.
class GroqClient {
  GroqClient({
    required Future<String?> Function() readApiKey,
    http.Client? httpClient,
  })  : _readApiKey = readApiKey,
        _http = httpClient ?? http.Client();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  final Future<String?> Function() _readApiKey;
  final http.Client _http;

  /// Mengembalikan isi `message.content` dari choice pertama.
  Future<String> complete({
    required String model,
    required List<Map<String, String>> messages,
    Map<String, dynamic>? responseFormat,
    String? reasoningEffort,
    double temperature = 0.2,
  }) async {
    final key = await _readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('Groq API key belum diatur di Settings.');
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      if (responseFormat != null) 'response_format': responseFormat,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    };

    final res = await _http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw GroqException(res.statusCode, res.body);
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>;
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>;
    return message['content'] as String;
  }
}
