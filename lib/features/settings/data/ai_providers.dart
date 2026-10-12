import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';
import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/core/ai/providers.dart';
import 'package:personal_finance_manager/core/db/providers.dart';

import 'settings_repository.dart';

export 'package:personal_finance_manager/core/ai/providers.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final llmClientProvider = Provider<LlmClient>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  final store = ref.watch(secureStoreProvider);
  return LlmClient(
    readConfig: settings.loadAiConfig,
    readApiKey: store.readAiKey,
  );
});

/// Dipakai layar Pengaturan; panggil `ref.invalidate` setelah menyimpan.
final aiConfigProvider = FutureProvider<AiConfig>(
  (ref) => ref.watch(settingsRepositoryProvider).loadAiConfig(),
);
