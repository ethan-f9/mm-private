import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/money/money.dart';

void main() {
  group('Money', () {
    test('IDR dan JPY tanpa desimal', () {
      expect(Money.fromDecimal(Decimal.parse('25000'), 'IDR').minor, 25000);
      expect(Money.fromDecimal(Decimal.parse('1200'), 'JPY').minor, 1200);
    });

    test('USD memakai 2 desimal', () {
      expect(Money.fromDecimal(Decimal.parse('12.34'), 'USD').minor, 1234);
      expect(Money(1234, 'USD').toDecimal(), Decimal.parse('12.34'));
    });

    test('penjumlahan dan pengurangan satu currency', () {
      expect(Money(100, 'IDR') + Money(50, 'IDR'), Money(150, 'IDR'));
      expect(Money(100, 'IDR') - Money(150, 'IDR'), Money(-50, 'IDR'));
    });

    test('lintas currency ditolak', () {
      expect(
        () => Money(100, 'IDR') + Money(100, 'USD'),
        throwsArgumentError,
      );
    });

    test('currency tidak dikenal ditolak', () {
      expect(() => Money.fromDecimal(Decimal.one, 'XXX'), throwsArgumentError);
    });
  });
}
