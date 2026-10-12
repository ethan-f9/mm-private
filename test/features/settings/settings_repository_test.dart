import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('config default kalau belum pernah disimpan', () async {
    final config = await settings.loadAiConfig();
    expect(config.baseUrl, AiConfig.defaultBaseUrl);
    expect(config.parserModel, AiConfig.defaultModel);
    expect(config.advisorModel, AiConfig.defaultModel);
  });

  test('simpan lalu muat kembali', () async {
    await settings.saveAiConfig(
      const AiConfig(
        baseUrl: 'https://openrouter.ai/api/v1',
        parserModel: 'model-a',
        advisorModel: 'model-b',
      ),
    );
    final config = await settings.loadAiConfig();
    expect(config.baseUrl, 'https://openrouter.ai/api/v1');
    expect(config.parserModel, 'model-a');
    expect(config.advisorModel, 'model-b');
  });

  test('simpan dua kali menimpa, bukan menambah baris', () async {
    await settings.set('k', '1');
    await settings.set('k', '2');
    expect(await settings.get('k'), '2');
    expect((await db.select(db.appSettings).get()).length, 1);
  });
}
