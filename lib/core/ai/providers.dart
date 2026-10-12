import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/security/secure_store.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
