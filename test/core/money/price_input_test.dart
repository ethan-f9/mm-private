import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/money/price_input.dart';

void main() {
  group('parseQuantity', () {
    test('pecahan dengan titik atau koma', () {
      expect(parseQuantity('0.005'), Decimal.parse('0.005'));
      expect(parseQuantity('0,005'), Decimal.parse('0.005'));
      expect(parseQuantity(' 10 '), Decimal.parse('10'));
    });

    test('tidak valid, nol, atau negatif ditolak', () {
      expect(parseQuantity(''), isNull);
      expect(parseQuantity('abc'), isNull);
      expect(parseQuantity('0'), isNull);
      expect(parseQuantity('-1'), isNull);
    });
  });

  group('parsePrice', () {
    test('IDR memakai format Indonesia', () {
      expect(parsePrice('9.500', 'IDR'), Decimal.parse('9500'));
      expect(parsePrice('1,35jt', 'IDR'), Decimal.parse('1350000'));
      expect(parsePrice('Rp 1.250.000', 'IDR'), Decimal.parse('1250000'));
    });

    test('currency lain: angka biasa', () {
      expect(parsePrice('150.25', 'USD'), Decimal.parse('150.25'));
      expect(parsePrice('150,25', 'USD'), Decimal.parse('150.25'));
    });

    test('tidak valid atau tidak positif ditolak', () {
      expect(parsePrice('', 'IDR'), isNull);
      expect(parsePrice('abc', 'USD'), isNull);
      expect(parsePrice('0', 'USD'), isNull);
      expect(parsePrice('-5', 'USD'), isNull);
    });
  });
}
