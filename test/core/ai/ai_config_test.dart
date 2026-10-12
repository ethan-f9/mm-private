import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';

void main() {
  group('AiConfig.validateBaseUrl', () {
    test('https valid', () {
      expect(AiConfig.validateBaseUrl('https://api.groq.com/openai/v1'), isNull);
      expect(AiConfig.validateBaseUrl('  https://openrouter.ai/api/v1  '), isNull);
    });

    test('http ditolak', () {
      expect(AiConfig.validateBaseUrl('http://api.example.com/v1'), isNotNull);
    });

    test('bukan URL ditolak', () {
      expect(AiConfig.validateBaseUrl('abc'), isNotNull);
      expect(AiConfig.validateBaseUrl(''), isNotNull);
    });
  });

  group('AiConfig.normalizeBaseUrl', () {
    test('buang spasi dan slash di ujung', () {
      expect(
        AiConfig.normalizeBaseUrl(' https://api.groq.com/openai/v1/// '),
        'https://api.groq.com/openai/v1',
      );
    });
  });

  test('chatCompletionsUri menambah path', () {
    expect(
      AiConfig.defaults.chatCompletionsUri.toString(),
      'https://api.groq.com/openai/v1/chat/completions',
    );
  });
}
