# Arsitektur

## Prinsip

- Storage lokal. Yang dikirim keluar: agregat ke Groq (inference cloud) dan harga/kurs dari API publik. Klaim "100% offline" tidak berlaku, jangan ditulis begitu.
- Project personal, sideload APK, satu user. Tidak ada consent flow, tidak ada multi-user.
- Uang tidak pernah `double`. Akun/transaksi = integer minor unit. Aset = `Decimal`.
- Angka turunan (saldo, average cost, gain) dihitung, tidak disimpan.
- LLM tidak menghitung. Dart menghitung, LLM menarasikan.

## Stack

| Lapisan | Pilihan |
|---|---|
| State | Riverpod (provider biasa dulu; codegen bisa ditambah nanti) |
| DB | Drift di atas SQLite, UUID PK, migrasi eksplisit |
| Routing | go_router |
| AI | Groq `openai/gpt-oss-120b`, BYOK, key di `flutter_secure_storage` |
| Harga | Crypto dan FX otomatis. IDX, reksadana, emas: input manual + timestamp |

## Layering

```
presentation  ->  provider  ->  repository  ->  DAO (Drift)
                      \-> domain (Dart murni, tanpa Flutter/Drift/http)
```

`domain` hanya ada di feature yang punya logic: investments, networth, advisor.
CRUD biasa (accounts, categories) cukup repository + provider.

## Skema

Lihat `lib/core/db/tables.dart`. Poin yang mudah terlupa:

- `transfers` terpisah dari `transactions`, supaya transfer tidak masuk laporan pengeluaran.
- Saldo akun = opening balance + transaksi + transfer + trade. Dihitung lewat query, tidak ada kolom `balance`.
- `net_worth_snapshots` di-backfill saat app dibuka, hari yang terlewat diisi carry-forward harga dan kurs terakhir.
- Emas dinilai dengan harga buyback, bukan harga beli.
- Target alokasi disimpan sebagai basis points (10000 = 100%), bukan float.
- Base currency IDR, tetap. IDR tanpa sen (scale 0).

## Pipeline advisor

1. Dart hitung: burn rate per kategori (fixed vs variable), delta vs periode sebelumnya, alokasi aktual vs target, drift per asset class, runway.
2. Kirim hanya agregat JSON ke Groq, bukan raw transaksi.
3. Minta output JSON terstruktur: insight, evidence (angka), severity.
4. Validasi di Dart: tiap angka di narasi harus ada di input. Insight tanpa evidence dibuang.
5. Cache hasil dengan hash input. Trigger manual atau mingguan, bukan background terus-menerus.

Aturan: data kurang dari ~60 hari = advisor bilang "data belum cukup". Tidak ada rekomendasi beli/jual instrumen spesifik, tidak ada prediksi harga. Risk profile = preset target alokasi yang bisa diedit (konservatif/moderat/agresif), bukan input prompt. Umur tidak dipakai.

Sebelum percaya 120b: bandingkan dengan 20b di 5-10 snapshot data tetap.

## Parsing teks AI

- Prompt berisi daftar akun dan kategori dari DB, plus tanggal hari ini.
- Model mengembalikan string nominal mentah; `IdAmountParser` yang menentukan angkanya.
- Selalu ada layar konfirmasi sebelum simpan. Tidak ada auto-save dari output LLM.
- Fallback form manual kalau offline atau kena rate limit.

## Urutan build

1. Fondasi + fase 1: DB, money, accounts, categories, transactions, transfers, saldo, net worth snapshot, backup JSON, biometrik.
2. Parser teks AI (ujung fase 1).
3. Fase 2: assets, trades, cost basis (test dulu), Update Harga manual, crypto + FX otomatis.
4. Fase 3: advisor, setelah 2-3 bulan data riil.

## Di luar scope (sengaja)

Receipt scanner/ML Kit, gamifikasi, Financial Health score, PDF report, merge-import (restore = wipe lalu load), FX gain/loss pada transfer lintas currency, stock split otomatis.

## Wajib di-test

Average cost, realized/unrealized gain, konversi FX, pembulatan per currency, parser nominal. UI tidak wajib.

## Backup

Auto-backup JSON mingguan ke folder pilihan (Storage Access Framework), lalu sync folder itu dengan Syncthing atau Drive. HP hilang = data hilang kalau ini tidak ada.
