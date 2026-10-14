import 'package:drift/drift.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';

import 'converters/decimal_converter.dart';
import 'enums.dart';

// Konvensi:
// - PK = UUID (text), supaya import/append tidak bentrok ID.
// - Uang akun/transaksi = integer minor unit + kolom currency.
// - Quantity & harga aset = Decimal (text).
// - Angka turunan (saldo, average cost, gain) TIDAK disimpan; dihitung via query/domain.

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get icon => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId =>
      text().customConstraint('NOT NULL REFERENCES accounts (id)')();
  TextColumn get categoryId =>
      text().nullable().customConstraint('REFERENCES categories (id)')();
  TextColumn get kind => textEnum<TxKind>()();

  /// Selalu positif; arah ditentukan oleh `kind`.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get source =>
      textEnum<TxSource>().withDefault(const Constant('manual'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Transfer antar akun = satu baris dua sisi. Tidak ikut laporan pengeluaran.
/// Transfer lintas currency: kurs implisit dari from/to amount.
class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get fromAccountId =>
      text().customConstraint('NOT NULL REFERENCES accounts (id)')();
  TextColumn get toAccountId =>
      text().customConstraint('NOT NULL REFERENCES accounts (id)')();
  IntColumn get fromAmountMinor => integer()();
  IntColumn get toAmountMinor => integer()();
  IntColumn get feeMinor => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<AssetType>()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get quantityScale => integer().withDefault(const Constant(8))();
  TextColumn get priceSource => textEnum<PriceSource>()();

  /// ID di penyedia harga otomatis (CoinGecko, mis. "bitcoin"). Null = manual.
  TextColumn get externalId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Trades extends Table {
  TextColumn get id => text()();
  TextColumn get assetId =>
      text().customConstraint('NOT NULL REFERENCES assets (id)')();
  TextColumn get fundingAccountId =>
      text().nullable().customConstraint('REFERENCES accounts (id)')();
  TextColumn get side => textEnum<TradeSide>()();
  TextColumn get quantity => text().map(const DecimalConverter())();
  TextColumn get price => text().map(const DecimalConverter())();

  /// Fee dalam minor unit currency aset.
  IntColumn get feeMinor => integer().withDefault(const Constant(0))();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PriceSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId =>
      text().customConstraint('NOT NULL REFERENCES assets (id)')();
  TextColumn get price => text().map(const DecimalConverter())();
  DateTimeColumn get fetchedAt => dateTime()();

  /// 'coingecko' | 'manual' | ...
  TextColumn get source => text()();
}

class FxRates extends Table {
  DateTimeColumn get date => dateTime()();
  TextColumn get base => text().withLength(min: 3, max: 3)();
  TextColumn get quote => text().withLength(min: 3, max: 3)();
  TextColumn get rate => text().map(const DecimalConverter())();

  @override
  Set<Column> get primaryKey => {date, base, quote};
}

class NetWorthSnapshots extends Table {
  DateTimeColumn get date => dateTime()();

  /// Total dalam base currency (IDR), minor unit.
  IntColumn get totalMinor => integer()();

  /// JSON: per asset class dan per currency.
  TextColumn get breakdownJson => text()();

  @override
  Set<Column> get primaryKey => {date};
}

/// Target alokasi per asset class dalam basis points (10000 = 100%).
class AllocationTargets extends Table {
  TextColumn get assetClass => text()();
  IntColumn get targetBps => integer()();

  @override
  Set<Column> get primaryKey => {assetClass};
}

class AdvisorInsights extends Table {
  TextColumn get id => text()();
  DateTimeColumn get generatedAt => dateTime()();

  /// Hash dari agregat input; sama = pakai cache, tidak panggil Groq lagi.
  TextColumn get inputHash => text()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Template transaksi (pengeluaran/pemasukan) yang dipakai ulang. Akun dan
/// nominal opsional; kategori harus bertipe sama dengan `kind`.
class TransactionTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get kind => textEnum<TxKind>()();
  TextColumn get accountId =>
      text().nullable().customConstraint('REFERENCES accounts (id)')();
  TextColumn get categoryId =>
      text().nullable().customConstraint('REFERENCES categories (id)')();
  IntColumn get amountMinor => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
