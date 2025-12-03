import 'package:flutter_test/flutter_test.dart';
import 'package:finantech/utils/currency_helper.dart';

void main() {
  group('CurrencyHelper', () {
    group('parseFromCurrency', () {
      test('deve converter string vazia para 0.0', () {
        expect(CurrencyHelper.parseFromCurrency(''), 0.0);
      });

      test('deve converter valor simples corretamente', () {
        expect(CurrencyHelper.parseFromCurrency('100,00'), 100.0);
      });

      test('deve converter valor com centavos corretamente', () {
        expect(CurrencyHelper.parseFromCurrency('1.234,56'), 1234.56);
      });

      test('deve converter valor grande com milhares', () {
        expect(CurrencyHelper.parseFromCurrency('10.000,00'), 10000.0);
        expect(CurrencyHelper.parseFromCurrency('1.000.000,99'), 1000000.99);
      });

      test('deve converter valor sem separador de milhares', () {
        expect(CurrencyHelper.parseFromCurrency('999,99'), 999.99);
      });

      test('deve retornar 0.0 para string inválida', () {
        expect(CurrencyHelper.parseFromCurrency('abc'), 0.0);
        expect(CurrencyHelper.parseFromCurrency('12abc34'), 0.0);
      });

      test('deve converter valores pequenos (centavos)', () {
        expect(CurrencyHelper.parseFromCurrency('0,01'), 0.01);
        expect(CurrencyHelper.parseFromCurrency('0,99'), 0.99);
      });
    });

    group('formatToCurrency', () {
      test('deve formatar valor inteiro com centavos', () {
        expect(CurrencyHelper.formatToCurrency(100.0), '100,00');
      });

      test('deve formatar valor com centavos', () {
        expect(CurrencyHelper.formatToCurrency(99.99), '99,99');
      });

      test('deve formatar valor com separador de milhares', () {
        expect(CurrencyHelper.formatToCurrency(1234.56), '1.234,56');
      });

      test('deve formatar valores grandes', () {
        expect(CurrencyHelper.formatToCurrency(10000.0), '10.000,00');
        expect(CurrencyHelper.formatToCurrency(1000000.99), '1.000.000,99');
      });

      test('deve formatar valor zero', () {
        expect(CurrencyHelper.formatToCurrency(0.0), '0,00');
      });

      test('deve formatar centavos pequenos', () {
        expect(CurrencyHelper.formatToCurrency(0.01), '0,01');
        expect(CurrencyHelper.formatToCurrency(0.10), '0,10');
      });

      test('deve arredondar para 2 casas decimais', () {
        expect(CurrencyHelper.formatToCurrency(10.999), '11,00');
        expect(CurrencyHelper.formatToCurrency(10.994), '10,99');
      });
    });

    group('formatWithSymbol', () {
      test('deve formatar com símbolo RS', () {
        expect(CurrencyHelper.formatWithSymbol(100.0), 'R\$ 100,00');
      });

      test('deve formatar valor grande com símbolo RS', () {
        expect(CurrencyHelper.formatWithSymbol(1500.50), 'R\$ 1.500,50');
      });

      test('deve formatar zero com símbolo RS', () {
        expect(CurrencyHelper.formatWithSymbol(0.0), 'R\$ 0,00');
      });
    });

    group('Conversão ida e volta', () {
      test('deve manter valor após parse e format', () {
        final valores = [100.0, 1234.56, 0.01, 999999.99, 0.0];

        for (final valor in valores) {
          final formatted = CurrencyHelper.formatToCurrency(valor);
          final parsed = CurrencyHelper.parseFromCurrency(formatted);
          expect(parsed, valor, reason: 'Falhou para valor: $valor');
        }
      });
    });
  });
}
