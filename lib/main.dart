import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:personal_finance_manager/core/widgets/amount_text.dart';
import 'package:personal_finance_manager/features/categories/data/category_repository.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';

  final container = ProviderContainer();
  await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();

  final stealth =
      await container.read(settingsRepositoryProvider).get(stealthSettingKey);
  container.read(stealthModeProvider.notifier).state = stealth == '1';

  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
