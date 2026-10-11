import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/money/id_amount_parser.dart';

void main() {
  group('IdAmountParser', () {
    test('suffix k / rb / ribu', () {
      expect(IdAmountParser.parse('25k'), 25000);
      expect(IdAmountParser.parse('25rb'), 25000);
      expect(IdAmountParser.parse('25 ribu'), 25000);
      expect(IdAmountParser.parse('25K'), 25000);
    });

    test('suffix jt / juta, koma dan titik desimal', () {
      expect(IdAmountParser.parse('2jt'), 2000000);
      expect(IdAmountParser.parse('2 juta'), 2000000);
      expect(IdAmountParser.parse('1,5jt'), 1500000);
      expect(IdAmountParser.parse('1.5jt'), 1500000);
    });

    test('format ribuan Indonesia', () {
      expect(IdAmountParser.parse('25.000'), 25000);
      expect(IdAmountParser.parse('1.500.000'), 1500000);
      expect(IdAmountParser.parse('15000'), 15000);
    });

    test('prefix Rp', () {
      expect(IdAmountParser.parse('Rp 25.000'), 25000);
      expect(IdAmountParser.parse('Rp. 25.000'), 25000);
      expect(IdAmountParser.parse('rp25000'), 25000);
    });

    test('titik ribuan + koma desimal', () {
      expect(IdAmountParser.parse('1.250.000,25'), 1250000);
    });

    test('input tidak valid mengembalikan null', () {
      expect(IdAmountParser.parse(''), isNull);
      expect(IdAmountParser.parse('abc'), isNull);
      expect(IdAmountParser.parse('25 kali'), isNull);
      expect(IdAmountParser.parse('1,2,3'), isNull);
    });
  });
}
