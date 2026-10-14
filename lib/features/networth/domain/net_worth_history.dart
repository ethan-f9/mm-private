import 'package:decimal/decimal.dart';
import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/core/money/currency_meta.dart';
import 'package:personal_finance_manager/features/investments/domain/cost_basis_calculator.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_cash.dart';

/// Net worth (IDR) pada akhir satu hari.
class NetWorthPoint {
  const NetWorthPoint({
    required this.date,
    required this.cashMinor,
    required this.investmentsMinor,
    required this.estimated,
    required this.complete,
  });

  /// Awal hari (jam 00:00).
  final DateTime date;
  final int cashMinor;
  final int investmentsMinor;

  /// True kalau sebagian nilai memakai pendekatan: kurs terdekat (belum ada
  /// kurs pada tanggal itu) atau harga beli (belum ada harga pada tanggal itu).
  final bool estimated;

  /// False kalau ada currency yang sama sekali tidak punya kurs (nilainya
  /// tidak ikut dijumlahkan).
  final bool complete;

  int get totalMinor => cashMinor + investmentsMinor;
}

class _CashEvent {
  const _CashEvent(this.at, this.accountId, this.delta);

  final DateTime at;
  final String accountId;
  final int delta;
}

/// Rekonstruksi net worth harian dari data mentah, TANPA menyimpan snapshot.
/// Jadi riwayat selalu sesuai data sekarang (hapus/ubah transaksi lama ikut
/// mengubah grafik). Aturan nilai pada hari D (sampai akhir hari D):
/// - kas = saldo awal + semua kejadian sampai D, per akun;
/// - aset = unit yang dimiliki pada D x harga terakhir yang tercatat sampai D;
///   belum ada harga -> dinilai pada modal (average cost);
/// - kurs = kurs terakhir sampai D; belum ada -> kurs tercatat paling awal
///   (ditandai estimasi).
/// [accounts] sudah disaring pemanggil (mis. tanpa akun arsip); kejadian milik
/// akun lain diabaikan, sama seperti net worth hari ini.
List<NetWorthPoint> computeNetWorthHistory({
  required DateTime today,
  required List<Account> accounts,
  required List<TransactionRow> transactions,
  required List<Transfer> transfers,
  required List<Trade> trades,
  required List<Asset> assets,
  required List<PriceSnapshot> prices,
  required List<FxRate> fxRates,
}) {
  const calculator = CostBasisCalculator();
  final accountById = {for (final a in accounts) a.id: a};
  final assetById = {for (final a in assets) a.id: a};

  final events = <_CashEvent>[];
  for (final t in transactions) {
    if (!accountById.containsKey(t.accountId)) continue;
    events.add(
      _CashEvent(
        t.occurredAt,
        t.accountId,
        t.kind == TxKind.income ? t.amountMinor : -t.amountMinor,
      ),
    );
  }
  for (final t in transfers) {
    if (accountById.containsKey(t.fromAccountId)) {
      events.add(
        _CashEvent(t.occurredAt, t.fromAccountId, -(t.fromAmountMinor + t.feeMinor)),
      );
    }
    if (accountById.containsKey(t.toAccountId)) {
      events.add(_CashEvent(t.occurredAt, t.toAccountId, t.toAmountMinor));
    }
  }
  for (final t in trades) {
    final fundingId = t.fundingAccountId;
    final asset = assetById[t.assetId];
    if (fundingId == null || asset == null || !accountById.containsKey(fundingId)) {
      continue;
    }
    events.add(
      _CashEvent(
        t.occurredAt,
        fundingId,
        tradeCashDeltaMinor(
          side: t.side,
          quantity: t.quantity,
          price: t.price,
          feeMinor: t.feeMinor,
          currency: asset.currency,
        ),
      ),
    );
  }
  events.sort((a, b) => a.at.compareTo(b.at));

  final times = <DateTime>[
    for (final e in events) e.at,
    for (final t in trades) t.occurredAt,
  ];
  if (times.isEmpty) return const [];
  final earliest = times.reduce((a, b) => a.isBefore(b) ? a : b);
  final start = DateTime(earliest.year, earliest.month, earliest.day);
  final lastDay = DateTime(today.year, today.month, today.day);
  if (start.isAfter(lastDay)) return const [];

  // Trade per aset (naik menurut waktu) dan cache posisi.
  final tradesByAsset = <String, List<Trade>>{};
  for (final t in trades) {
    if (assetById.containsKey(t.assetId)) {
      tradesByAsset.putIfAbsent(t.assetId, () => []).add(t);
    }
  }
  for (final list in tradesByAsset.values) {
    list.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }
  final tradeCount = <String, int>{};
  final positions = <String, PositionSummary>{};

  // Harga per aset (naik menurut waktu) dan penunjuk.
  final pricesByAsset = <String, List<PriceSnapshot>>{};
  for (final p in prices) {
    pricesByAsset.putIfAbsent(p.assetId, () => []).add(p);
  }
  for (final list in pricesByAsset.values) {
    list.sort((a, b) {
      final byTime = a.fetchedAt.compareTo(b.fetchedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }
  final priceIdx = <String, int>{};

  // Kurs per currency (naik menurut tanggal) dan penunjuk.
  final fxByBase = <String, List<FxRate>>{};
  for (final r in fxRates) {
    if (r.quote == CurrencyMeta.baseCurrency) {
      fxByBase.putIfAbsent(r.base, () => []).add(r);
    }
  }
  for (final list in fxByBase.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
  }
  final fxIdx = <String, int>{for (final k in fxByBase.keys) k: -1};

  final balances = {for (final a in accounts) a.id: a.openingBalanceMinor};
  var eventIdx = 0;
  final points = <NetWorthPoint>[];

  for (var day = start;
      !day.isAfter(lastDay);
      day = DateTime(day.year, day.month, day.day + 1)) {
    final dayEnd = DateTime(day.year, day.month, day.day + 1);

    while (eventIdx < events.length && events[eventIdx].at.isBefore(dayEnd)) {
      final e = events[eventIdx];
      balances[e.accountId] = (balances[e.accountId] ?? 0) + e.delta;
      eventIdx++;
    }

    // Kurs pada hari ini.
    final rates = <String, Decimal>{};
    final fallbackBases = <String>{};
    fxByBase.forEach((base, list) {
      var idx = fxIdx[base]!;
      while (idx + 1 < list.length && list[idx + 1].date.isBefore(dayEnd)) {
        idx++;
      }
      fxIdx[base] = idx;
      if (idx >= 0) {
        rates[base] = list[idx].rate;
      } else {
        rates[base] = list.first.rate;
        fallbackBases.add(base);
      }
    });
    final fx = FxTable(rates);

    var estimated = false;
    var complete = true;

    // Kas: jumlahkan per currency dulu, baru konversi (sama dengan net worth hari ini).
    final cashByCurrency = <String, int>{};
    for (final a in accounts) {
      cashByCurrency[a.currency] =
          (cashByCurrency[a.currency] ?? 0) + (balances[a.id] ?? 0);
    }
    var cash = 0;
    cashByCurrency.forEach((currency, minor) {
      if (currency == CurrencyMeta.baseCurrency) {
        cash += minor;
        return;
      }
      final converted = fx.toBaseMinor(minor, currency);
      if (converted == null) {
        complete = false;
      } else {
        cash += converted;
        if (fallbackBases.contains(currency)) estimated = true;
      }
    });

    // Investasi.
    var investments = 0;
    for (final entry in tradesByAsset.entries) {
      final asset = assetById[entry.key]!;
      final list = entry.value;

      var count = tradeCount[asset.id] ?? 0;
      final previous = count;
      while (count < list.length && list[count].occurredAt.isBefore(dayEnd)) {
        count++;
      }
      if (count != previous || !positions.containsKey(asset.id)) {
        tradeCount[asset.id] = count;
        try {
          positions[asset.id] = calculator.compute([
            for (var i = 0; i < count; i++) toTradeInput(list[i], asset.currency),
          ]);
        } on OversellException {
          positions[asset.id] = calculator.compute(const []);
        }
      }
      final position = positions[asset.id]!;
      if (position.units <= Decimal.zero) continue;

      final priceList = pricesByAsset[asset.id];
      Decimal? price;
      if (priceList != null) {
        var idx = priceIdx[asset.id] ?? -1;
        while (idx + 1 < priceList.length &&
            priceList[idx + 1].fetchedAt.isBefore(dayEnd)) {
          idx++;
        }
        priceIdx[asset.id] = idx;
        if (idx >= 0) price = priceList[idx].price;
      }

      final Decimal value;
      if (price == null) {
        value = position.totalCost;
        estimated = true;
      } else {
        value = position.units * price;
      }

      final converted = fx.decimalToBaseMinor(value, asset.currency);
      if (converted == null) {
        complete = false;
      } else {
        investments += converted;
        if (fallbackBases.contains(asset.currency)) estimated = true;
      }
    }

    points.add(
      NetWorthPoint(
        date: day,
        cashMinor: cash,
        investmentsMinor: investments,
        estimated: estimated,
        complete: complete,
      ),
    );
  }

  return points;
}

/// Potong riwayat ke [days] hari terakhir (0 = semua).
List<NetWorthPoint> sliceHistory(
  List<NetWorthPoint> all,
  int days,
  DateTime today,
) {
  if (days <= 0) return all;
  final cutoff = DateTime(today.year, today.month, today.day - days);
  return [for (final p in all) if (!p.date.isBefore(cutoff)) p];
}
