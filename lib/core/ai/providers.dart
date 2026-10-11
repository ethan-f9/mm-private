import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/security/secure_store.dart';

import 'groq_client.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final groqClientProvider = Provider<GroqClient>((ref) {
  final store = ref.watch(secureStoreProvider);
  return GroqClient(readApiKey: store.readGroqKey);
});
