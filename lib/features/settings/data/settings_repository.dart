import 'package:drift/drift.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';

/// Key-value sederhana di tabel `app_settings`. Hanya untuk data non-rahasia.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _kBaseUrl = 'ai.base_url';
  static const _kParserModel = 'ai.parser_model';
  static const _kAdvisorModel = 'ai.advisor_model';

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<AiConfig> loadAiConfig() async {
    return AiConfig(
      baseUrl: await get(_kBaseUrl) ?? AiConfig.defaultBaseUrl,
      parserModel: await get(_kParserModel) ?? AiConfig.defaultModel,
      advisorModel: await get(_kAdvisorModel) ?? AiConfig.defaultModel,
    );
  }

  Future<void> saveAiConfig(AiConfig config) async {
    await set(_kBaseUrl, config.baseUrl);
    await set(_kParserModel, config.parserModel);
    await set(_kAdvisorModel, config.advisorModel);
  }
}
