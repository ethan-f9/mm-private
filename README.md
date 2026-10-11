# Personal Finance & Multi-Asset Manager

Android, Flutter, offline-first. Storage lokal (Drift/SQLite). AI call ke Groq (BYOK).
Keputusan arsitektur ada di `docs/ARCHITECTURE.md`.

## Setup

```bash
cd personal_finance_manager
flutter create . --platforms=android --org com.namakamu   # generate folder android/
# kalau muncul test/widget_test.dart hasil generate, hapus filenya
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate app_database.g.dart
flutter test
flutter run
```

Skeleton ini belum pernah di-compile. Kalau `pub get` protes versi, jalankan
`flutter pub upgrade --major-versions` lalu perbaiki API yang berubah.
Titik paling mungkin kena: API package `decimal` (`shift`, `Rational.toDecimal`)
di `money.dart` dan `cost_basis_calculator.dart`.

## Setelah `flutter create`

- `android/app/build.gradle`: set `minSdk = 23` (syarat `flutter_secure_storage`).
- `local_auth`: `MainActivity` harus extend `FlutterFragmentActivity`, dan tambah
  permission `USE_BIOMETRIC` di `AndroidManifest.xml`. Belum dipakai di kode.
- Groq API key tidak ada di repo. Input lewat layar Settings (belum dibuat),
  tersimpan di `flutter_secure_storage`.

## Status

| Bagian | Status |
|---|---|
| Struktur folder feature-first | siap |
| `core/money` (Money, CurrencyMeta, parser nominal ID) + test | siap |
| `core/db` (tabel Drift, converter Decimal) | siap, butuh build_runner |
| `investments/domain/cost_basis_calculator` + test | siap |
| `core/ai/groq_client`, `core/security/secure_store` | stub tipis |
| DAO, repository, UI, router | placeholder |
