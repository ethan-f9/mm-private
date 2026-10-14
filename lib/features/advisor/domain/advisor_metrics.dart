import 'package:personal_finance_manager/core/db/app_database.dart';
import 'package:personal_finance_manager/core/db/enums.dart';
import 'package:personal_finance_manager/features/investments/domain/fx_table.dart';
import 'package:personal_finance_manager/features/investments/domain/portfolio.dart';
import 'package:personal_finance_manager/features/networth/domain/net_worth.dart';

import 'allocation_presets.dart';

/// Minimal rentang data (hari) sebelum angka bulanan dianggap bermakna.
const advisorMinDataDays = 60;

class MonthTotals {
  const MonthTotals(this.month, this.incomeMinor, this.expenseMinor);

  /// Tanggal 1 bulan itu.
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
}

class CategoryTrend {
  const CategoryTrend({
    required this.name,
    required this.last30Minor,
    required this.prev30Minor,
    required this.changePct,
  });

  final String name;
  final int last30Minor;
  final int prev30Minor;

  /// Null kalau 30 hari sebelumnya nol (tidak ada pembanding).
  final double? changePct;
}

class AllocationRow {
  const AllocationRow({
    required this.classKey,
    required this.valueMinor,
    required this.actualPct,
    required this.targetPct,
    required this.driftPts,
  });

  final String classKey;
  final int valueMinor;
  final double? actualPct;
  final double? targetPct;

  /// Aktual dikurangi target, dalam poin persentase.
  final double? driftPts;
}

/// Semua angka advisor dihitung di sini (Dart), bukan oleh model AI.
class AdvisorMetrics {
  const AdvisorMetrics({
    required this.dataSpanDays,
    required this.hasEnoughData,
    required this.months,
    required this.avgMonthlyExpenseMinor,
    required this.avgMonthlyIncomeMinor,
    required this.savingsRatePct,
    required this.cashMinor,
    required this.runwayMonths,
    required this.categoryTrends,
    required this.allocation,
    required this.hasTargets,
    required this.missingFx,
  });

  final int dataSpanDays;
  final bool hasEnoughData;

  /// Bulan penuh terakhir (maks. 3), dari yang terlama.
  final List<MonthTotals> months;
  final int? avgMonthlyExpenseMinor;
  final int? avgMonthlyIncomeMinor;
  final double? savingsRatePct;
  final int cashMinor;

  /// Kas dibagi rata-rata pengeluaran bulanan. Null kalau pengeluaran nol.
  final double? runwayMonths;
  final List<CategoryTrend> categoryTrends;
  final List<AllocationRow> allocation;
  final bool hasTargets;

  /// Currency yang kursnya belum ada; transaksi/aset terkait tidak dihitung.
  final Set<String> missingFx;
}

AdvisorMetrics computeAdvisorMetrics({
  required DateTime now,
  required List<TransactionRow> transactions,
  required Map<String, String> categoryNames,
  required NetWorth netWorth,
  required List<Holding> holdings,
  required FxTable fx,
  required Map<String, int>? targetBps,
}) {
  final missing = <String>{...netWorth.missingFx};

  int? toBase(TransactionRow t) {
    final value = fx.toBaseMinor(t.amountMinor, t.currency);
    if (value == null) missing.add(t.currency);
    return value;
  }

  DateTime? earliest;
  for (final t in transactions) {
    if (earliest == null || t.occurredAt.isBefore(earliest)) {
      earliest = t.occurredAt;
    }
  }
  final span = earliest == null ? 0 : now.difference(earliest).inDays;

  // Bulan penuh sebelum bulan berjalan. Bulan pertama data dilewati kalau
  // pencatatan baru mulai setelah tanggal 7 (bulannya tidak lengkap).
  final months = <MonthTotals>[];
  if (earliest != null) {
    final earliestMonth = DateTime(earliest.year, earliest.month);
    for (var i = 3; i >= 1; i--) {
      final start = DateTime(now.year, now.month - i);
      final end = DateTime(now.year, now.month - i + 1);
      if (start.isBefore(earliestMonth)) continue;
      if (start == earliestMonth && earliest.day > 7) continue;

      var income = 0;
      var expense = 0;
      for (final t in transactions) {
        if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) continue;
        final value = toBase(t);
        if (value == null) continue;
        if (t.kind == TxKind.income) {
          income += value;
        } else {
          expense += value;
        }
      }
      months.add(MonthTotals(start, income, expense));
    }
  }

  int? avgExpense;
  int? avgIncome;
  double? savingsRate;
  if (months.isNotEmpty) {
    avgExpense =
        (months.fold<int>(0, (s, m) => s + m.expenseMinor) / months.length).round();
    avgIncome =
        (months.fold<int>(0, (s, m) => s + m.incomeMinor) / months.length).round();
    if (avgIncome > 0) {
      savingsRate = (avgIncome - avgExpense) / avgIncome * 100;
    }
  }

  final cash = netWorth.cashMinor;
  double? runway;
  if (avgExpense != null && avgExpense > 0) {
    runway = cash <= 0 ? 0 : cash / avgExpense;
  }

  // Tren kategori: 30 hari terakhir vs 30 hari sebelumnya.
  final last30From = now.subtract(const Duration(days: 30));
  final prev30From = now.subtract(const Duration(days: 60));
  final last = <String, int>{};
  final prev = <String, int>{};
  for (final t in transactions) {
    if (t.kind != TxKind.expense) continue;
    final value = toBase(t);
    if (value == null) continue;
    final name = categoryNames[t.categoryId] ?? 'Tanpa kategori';
    final at = t.occurredAt;
    if (at.isAfter(last30From) && !at.isAfter(now)) {
      last[name] = (last[name] ?? 0) + value;
    } else if (at.isAfter(prev30From) && !at.isAfter(last30From)) {
      prev[name] = (prev[name] ?? 0) + value;
    }
  }
  final ranked = last.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final trends = [
    for (final e in ranked.take(5))
      CategoryTrend(
        name: e.key,
        last30Minor: e.value,
        prev30Minor: prev[e.key] ?? 0,
        changePct: (prev[e.key] ?? 0) > 0
            ? (e.value - prev[e.key]!) / prev[e.key]! * 100
            : null,
      ),
  ];

  // Alokasi aktual per kelas aset (IDR). Aset tanpa harga dinilai pada modal.
  final values = <String, int>{for (final k in assetClassKeys) k: 0};
  values['cash'] = cash < 0 ? 0 : cash;
  for (final h in holdings) {
    if (!h.isHeld) continue;
    final value = fx.decimalToBaseMinor(
      h.marketValue ?? h.position.totalCost,
      h.asset.currency,
    );
    if (value == null) {
      missing.add(h.asset.currency);
      continue;
    }
    final key = h.asset.type.name;
    values[key] = (values[key] ?? 0) + value;
  }
  final total = values.values.fold<int>(0, (s, v) => s + v);
  final hasTargets = targetBps != null && targetBps.isNotEmpty;
  final allocation = [
    for (final key in assetClassKeys)
      () {
        final actual = total > 0 ? values[key]! / total * 100 : null;
        final target = hasTargets ? (targetBps[key] ?? 0) / 100 : null;
        return AllocationRow(
          classKey: key,
          valueMinor: values[key]!,
          actualPct: actual,
          targetPct: target,
          driftPts: (actual != null && target != null) ? actual - target : null,
        );
      }(),
  ];

  return AdvisorMetrics(
    dataSpanDays: span,
    hasEnoughData: span >= advisorMinDataDays && months.isNotEmpty,
    months: months,
    avgMonthlyExpenseMinor: avgExpense,
    avgMonthlyIncomeMinor: avgIncome,
    savingsRatePct: savingsRate,
    cashMinor: cash,
    runwayMonths: runway,
    categoryTrends: trends,
    allocation: allocation,
    hasTargets: hasTargets,
    missingFx: missing,
  );
}
