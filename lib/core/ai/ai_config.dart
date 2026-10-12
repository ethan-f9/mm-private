/// Konfigurasi provider AI. Semua provider yang mendukung endpoint
/// `POST {baseUrl}/chat/completions` gaya OpenAI bisa dipakai (Groq, OpenRouter,
/// Gemini endpoint OpenAI-compatible, dll). API key TIDAK disimpan di sini,
/// melainkan di SecureStore.
class AiConfig {
  const AiConfig({
    required this.baseUrl,
    required this.parserModel,
    required this.advisorModel,
  });

  static const defaultBaseUrl = 'https://api.groq.com/openai/v1';
  static const defaultModel = 'openai/gpt-oss-120b';

  static const defaults = AiConfig(
    baseUrl: defaultBaseUrl,
    parserModel: defaultModel,
    advisorModel: defaultModel,
  );

  final String baseUrl;

  /// Model untuk parsing teks bebas menjadi transaksi.
  final String parserModel;

  /// Model untuk narasi advisor.
  final String advisorModel;

  Uri get chatCompletionsUri => Uri.parse('$baseUrl/chat/completions');

  /// Return null kalau valid, atau pesan error.
  static String? validateBaseUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return 'URL tidak valid';
    }
    if (uri.scheme != 'https') {
      return 'Wajib https:// supaya API key tidak terkirim polos';
    }
    return null;
  }

  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
