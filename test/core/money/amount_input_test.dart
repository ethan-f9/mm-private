import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/money/amount_input.dart';
import 'package:personal_finance_manager/core/money/money_format.dart';

void main() {
  group('parseAmountMinor', () {
    test('IDR memakai parser Indonesia', () {
      expect(parseAmountMinor('25k', 'IDR'), 25000);
      expect(parseAmountMinor('1,5jt', 'IDR'), 1500000);
    });

    test('USD: titik atau koma desimal ke minor unit', () {
      expect(parseAmountMinor('12.34', 'USD'), 1234);
      expect(parseAmountMinor('12,34', 'USD'), 1234);
      expect(parseAmountMinor('100', 'USD'), 10000);
    });

    test('JPY tanpa desimal', () {
      expect(parseAmountMinor('1200', 'JPY'), 1200);
    });

    test('input tidak valid atau kosong', () {
      expect(parseAmountMinor('abc', 'USD'), isNull);
      expect(parseAmountMinor('', 'IDR'), isNull);
      expect(parseAmountMinor('   ', 'USD'), isNull);
    });
  });

  group('formatMinor', () {
    test('IDR dengan pemisah ribuan titik', () {
      expect(formatMinor(1250000, 'IDR'), contains('1.250.000'));
      expect(formatMinor(1250000, 'IDR'), contains('Rp'));
    });

    test('USD dengan desimal koma', () {
      expect(formatMinor(1234, 'USD'), contains('12,34'));
    });
  });
}
