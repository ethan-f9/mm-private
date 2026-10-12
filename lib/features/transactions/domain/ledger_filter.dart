import 'package:personal_finance_manager/core/db/enums.dart';

import 'ledger_item.dart';

enum LedgerKind { all, expense, income, transfer }

/// Rentang waktu [from, to). `to` eksklusif.
class LedgerRange {
  const LedgerRange(this.from, this.to);

  factory LedgerRange.month(DateTime month) => LedgerRange(
        DateTime(month.year, month.month),
        DateTime(month.year, month.month + 1),
      );

  /// Semua tanggal (dipakai saat mencari tanpa rentang yang dipilih).
  static final LedgerRange all = LedgerRange(DateTime(2000), DateTime(2100));

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is LedgerRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class LedgerFilter {
  const LedgerFilter({
    this.query = '',
    this.kind = LedgerKind.all,
    this.range,
  });

  final String query;
  final LedgerKind kind;

  /// Rentang tanggal pilihan user. Null = pakai bulan yang sedang dilihat.
  final LedgerRange? range;

  bool get isSearching => query.trim().isNotEmpty;

  LedgerFilter copyWith({
    String? query,
    LedgerKind? kind,
    LedgerRange? range,
    bool clearRange = false,
  }) {
    return LedgerFilter(
      query: query ?? this.query,
      kind: kind ?? this.kind,
      range: clearRange ? null : (range ?? this.range),
    );
  }
}

/// Rentang data yang harus dimuat:
/// rentang pilihan user > semua tanggal (kalau sedang mencari) > bulan aktif.
LedgerRange effectiveRange(LedgerFilter filter, DateTime month) {
  return filter.range ??
      (filter.isSearching ? LedgerRange.all : LedgerRange.month(month));
}

/// Filter jenis dan pencarian. Pencarian cocok dengan catatan atau nama
/// kategori (huruf besar/kecil diabaikan).
List<LedgerItem> applyLedgerFilter(
  List<LedgerItem> items,
  LedgerFilter filter, {
  required Map<String, String> categoryNames,
}) {
  final q = filter.query.trim().toLowerCase();

  return items.where((item) {
    switch (item) {
      case TransactionItem(:final row):
        if (filter.kind == LedgerKind.transfer) return false;
        if (filter.kind == LedgerKind.expense && row.kind != TxKind.expense) {
          return false;
        }
        if (filter.kind == LedgerKind.income && row.kind != TxKind.income) {
          return false;
        }
        if (q.isEmpty) return true;
        final note = (row.note ?? '').toLowerCase();
        final category = (categoryNames[row.categoryId] ?? '').toLowerCase();
        return note.contains(q) || category.contains(q);
      case TransferItem(:final transfer):
        if (filter.kind != LedgerKind.all && filter.kind != LedgerKind.transfer) {
          return false;
        }
        if (q.isEmpty) return true;
        return (transfer.note ?? '').toLowerCase().contains(q);
    }
  }).toList();
}

class DayGroup {
  const DayGroup(this.day, this.items);

  /// Tanggal tanpa jam.
  final DateTime day;
  final List<LedgerItem> items;
}

/// Kelompokkan per hari. [items] harus sudah terurut dari terbaru.
List<DayGroup> groupByDay(List<LedgerItem> items) {
  final groups = <DayGroup>[];
  DateTime? currentDay;
  var current = <LedgerItem>[];

  for (final item in items) {
    final t = item.occurredAt;
    final day = DateTime(t.year, t.month, t.day);
    if (currentDay == null || day != currentDay) {
      if (currentDay != null) groups.add(DayGroup(currentDay, current));
      currentDay = day;
      current = <LedgerItem>[];
    }
    current.add(item);
  }
  if (currentDay != null) groups.add(DayGroup(currentDay, current));
  return groups;
}

/// Pemasukan dikurangi pengeluaran pada hari itu untuk satu currency.
/// Transfer tidak dihitung. Null kalau tidak ada transaksi di currency itu.
int? dailyNetMinor(DayGroup group, String currency) {
  int? net;
  for (final item in group.items) {
    if (item is TransactionItem && item.row.currency == currency) {
      final signed = item.row.kind == TxKind.income
          ? item.row.amountMinor
          : -item.row.amountMinor;
      net = (net ?? 0) + signed;
    }
  }
  return net;
}
