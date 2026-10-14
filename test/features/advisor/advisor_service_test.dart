import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';
import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_repository.dart';
import 'package:personal_finance_manager/features/advisor/data/advisor_service.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_input.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_metrics.dart';
import 'package:personal_finance_manager/features/advisor/domain/advisor_validator.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

import 'advisor_test_support.dart';

void main() {
  late AppDatabase db;
  late AdvisorRepository repository;
  late AdvisorMetrics metrics;
  late List<http.Request> requests;
  late String llmContent;
  late AdvisorService service;

  const goodInsight = {
    'severity': 'warning',
    'title': 'Pengeluaran Makanan naik',
    'detail': 'Makanan naik +50,0% dibanding 30 hari sebelumnya.',
    'evidence': ['Makanan Rp 1.500.000 vs Rp 1.000.000 (+50,0%)'],
  };
  const hallucinated = {
    'severity': 'critical',
    'title': 'Runway kritis',
    'detail': 'Runway hanya 1,2 bulan.',
    'evidence': ['Kas Rp 15.000.000'],
  };

  String chatBody(String content) => jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      });

  setUp(() async {
    db = newDb();
    repository = AdvisorRepository(db);
    metrics = await scenarioMetrics(db);
    requests = [];
    llmContent = jsonEncode({'insights': [goodInsight]});

    service = AdvisorService(
      llm: LlmClient(
        readConfig: () async => AiConfig.defaults,
        readApiKey: () async => 'kunci-rahasia',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(chatBody(llmContent), 200);
        }),
      ),
      settings: SettingsRepository(db),
      repository: repository,
      clock: () => scenarioNow,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('insight valid: dikembalikan dan disimpan dengan hash input', () async {
    final payload = await service.generate(metrics);

    expect(payload.items.length, 1);
    expect(payload.dropped, 0);
    expect(payload.model, AiConfig.defaultModel);

    final saved = (await repository.watchLatest().first)!;
    expect(saved.inputHash, AdvisorService.hashFor(metrics));
    expect(saved.generatedAt, scenarioNow);
    final back = AdvisorPayload.fromJson(
      jsonDecode(saved.payloadJson) as Map<String, dynamic>,
    );
    expect(back.items.single.title, 'Pengeluaran Makanan naik');
  });

  test('JSON berpagar markdown diterima', () async {
    llmContent = 'Tentu:\n```json\n${jsonEncode({'insights': [goodInsight]})}\n```';
    final payload = await service.generate(metrics);
    expect(payload.items.length, 1);
  });

  test('sebagian insight berangka karangan dibuang, sisanya disimpan', () async {
    llmContent = jsonEncode({'insights': [goodInsight, hallucinated]});
    final payload = await service.generate(metrics);
    expect(payload.items.length, 1);
    expect(payload.dropped, 1);
  });

  test('semua insight dibuang: melempar dan tidak menyimpan apa pun', () async {
    llmContent = jsonEncode({'insights': [hallucinated]});
    await expectLater(
      service.generate(metrics),
      throwsA(isA<AdvisorException>()),
    );
    expect(await repository.watchLatest().first, isNull);
  });

  test('jawaban bukan JSON: melempar', () async {
    llmContent = 'maaf, saya tidak bisa';
    await expectLater(
      service.generate(metrics),
      throwsA(isA<AdvisorException>()),
    );
    expect(await repository.watchLatest().first, isNull);
  });

  test('data belum cukup: melempar tanpa memanggil AI', () async {
    final fresh = newDb();
    final thin = computeAdvisorMetrics(
      now: scenarioNow,
      transactions: const [],
      categoryNames: const {},
      netWorth: netWorthWithCash(0),
      holdings: const [],
      fx: FxTable.empty,
      targetBps: null,
    );
    await fresh.close();

    await expectLater(
      service.generate(thin),
      throwsA(
        isA<AdvisorException>().having((e) => e.message, 'pesan', contains('Data belum cukup')),
      ),
    );
    expect(requests, isEmpty);
  });

  test('permintaan ke AI: memakai model advisor, kunci, dan hanya agregat', () async {
    await service.generate(metrics);

    final request = requests.single;
    expect(request.headers['Authorization'], 'Bearer kunci-rahasia');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], AiConfig.defaultModel);

    final messages = body['messages'] as List;
    expect((messages[0] as Map)['content'], advisorSystemPrompt);
    final data = (messages[1] as Map)['content'] as String;
    expect(data, startsWith('DATA:'));
    expect(data, contains('Rp 5.000.000'));
    expect(data, isNot(contains('rahasia-merchant')));
    expect(data, isNot(contains('Cash')));
  });

  test('riwayat insight dipangkas ke 20 terbaru', () async {
    for (var i = 0; i < 23; i++) {
      await repository.save(
        inputHash: 'h$i',
        payloadJson: '{}',
        at: DateTime(2026, 10, 1).add(Duration(hours: i)),
      );
    }
    final rows = await db.select(db.advisorInsights).get();
    expect(rows.length, AdvisorRepository.keepCount);
    expect(rows.any((r) => r.inputHash == 'h0'), isFalse); // terlama dibuang
    expect(rows.any((r) => r.inputHash == 'h22'), isTrue);
  });

  test('hashFor berubah kalau data berubah', () async {
    final other = await scenarioMetrics(newDb(), cash: 1000);
    expect(AdvisorService.hashFor(other), isNot(AdvisorService.hashFor(metrics)));
  });
}
