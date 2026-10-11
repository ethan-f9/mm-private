import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/features/investments/domain/cost_basis_calculator.dart';
import 'package:personal_finance_manager/features/investments/domain/trade_side.dart';

Decimal d(String s) => Decimal.parse(s);

TradeInput trade(
  TradeSide side,
  String qty,
  String price, {
  String fee = '0',
  required DateTime at,
}) =>
    TradeInput(
      side: side,
      quantity: d(qty),
      price: d(price),
      fee: d(fee),
      occurredAt: at,
    );

void main() {
  const calc = CostBasisCalculator();
  final t1 = DateTime(2026, 1, 1);
  final t2 = DateTime(2026, 2, 1);
  final t3 = DateTime(2026, 3, 1);

  test('average cost dari dua pembelian', () {
    final r = calc.compute([
      trade(TradeSide.buy, '10', '100', at: t1),
      trade(TradeSide.buy, '10', '200', at: t2),
    ]);
    expect(r.units, d('20'));
    expect(r.totalCost, d('3000'));
    expect(r.averageCost, d('150'));
  });

  test('penjualan sebagian: realized gain dan sisa cost', () {
    final r = calc.compute([
      trade(TradeSide.buy, '10', '100', at: t1),
      trade(TradeSide.buy, '10', '200', at: t2),
      trade(TradeSide.sell, '5', '200', at: t3),
    ]);
    expect(r.units, d('15'));
    expect(r.realizedGain, d('250'));
    expect(r.totalCost, d('2250'));
    expect(r.averageCost, d('150'));
    expect(r.unrealizedGain(d('200')), d('750'));
  });

  test('fee beli masuk cost basis, fee jual mengurangi hasil', () {
    final r = calc.compute([
      trade(TradeSide.buy, '10', '100', fee: '10', at: t1),
      trade(TradeSide.sell, '10', '110', fee: '10', at: t2),
    ]);
    // cost 1010, hasil 1090
    expect(r.realizedGain, d('80'));
    expect(r.units, Decimal.zero);
    expect(r.totalCost, Decimal.zero);
  });

  test('urutan input tidak penting, diurutkan berdasarkan tanggal', () {
    final r = calc.compute([
      trade(TradeSide.sell, '5', '200', at: t3),
      trade(TradeSide.buy, '10', '100', at: t1),
      trade(TradeSide.buy, '10', '200', at: t2),
    ]);
    expect(r.units, d('15'));
    expect(r.realizedGain, d('250'));
  });

  test('jual melebihi unit melempar OversellException', () {
    expect(
      () => calc.compute([
        trade(TradeSide.buy, '5', '100', at: t1),
        trade(TradeSide.sell, '6', '100', at: t2),
      ]),
      throwsA(isA<OversellException>()),
    );
  });

  test('dividen tidak mengubah posisi', () {
    final r = calc.compute([
      trade(TradeSide.buy, '10', '100', at: t1),
      trade(TradeSide.dividend, '10', '5', at: t2),
    ]);
    expect(r.units, d('10'));
    expect(r.totalCost, d('1000'));
    expect(r.dividendIncome, d('50'));
  });

  test('pecahan crypto 8 desimal', () {
    final r = calc.compute([
      trade(TradeSide.buy, '0.00500000', '1000000000', at: t1),
    ]);
    expect(r.units, d('0.005'));
    expect(r.totalCost, d('5000000'));
  });
}
