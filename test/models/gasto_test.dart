import 'package:flutter_test/flutter_test.dart';
import 'package:finantech/models/gasto.dart';

void main() {
  group('Gasto Model', () {
    test('deve criar um Gasto com todos os campos', () {
      final gasto = Gasto(
        id: 1,
        origem: 'Santander',
        valor: 1500.50,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: '2025-12-03T10:00:00.000Z',
      );

      expect(gasto.id, 1);
      expect(gasto.origem, 'Santander');
      expect(gasto.valor, 1500.50);
      expect(gasto.pago, false);
      expect(gasto.mes, 12);
      expect(gasto.ano, 2025);
      expect(gasto.createdAt, '2025-12-03T10:00:00.000Z');
    });

    test('deve criar Gasto sem id (para inserção)', () {
      final gasto = Gasto(
        origem: 'Inter',
        valor: 200.00,
        pago: true,
        mes: 1,
        ano: 2026,
        createdAt: '2026-01-01T00:00:00.000Z',
      );

      expect(gasto.id, isNull);
      expect(gasto.origem, 'Inter');
    });

    group('fromMap', () {
      test('deve converter Map para Gasto corretamente', () {
        final map = {
          'id': 5,
          'origem': 'Nubank',
          'valor': 999.99,
          'pago': 1,
          'mes': 6,
          'ano': 2025,
          'createdAt': '2025-06-15T12:30:00.000Z',
        };

        final gasto = Gasto.fromMap(map);

        expect(gasto.id, 5);
        expect(gasto.origem, 'Nubank');
        expect(gasto.valor, 999.99);
        expect(gasto.pago, true);
        expect(gasto.mes, 6);
        expect(gasto.ano, 2025);
      });

      test('deve converter pago = 0 para false', () {
        final map = {
          'id': 1,
          'origem': 'Teste',
          'valor': 100.0,
          'pago': 0,
          'mes': 1,
          'ano': 2025,
          'createdAt': '2025-01-01T00:00:00.000Z',
        };

        final gasto = Gasto.fromMap(map);
        expect(gasto.pago, false);
      });

      test('deve converter pago = 1 para true', () {
        final map = {
          'id': 1,
          'origem': 'Teste',
          'valor': 100.0,
          'pago': 1,
          'mes': 1,
          'ano': 2025,
          'createdAt': '2025-01-01T00:00:00.000Z',
        };

        final gasto = Gasto.fromMap(map);
        expect(gasto.pago, true);
      });

      test('deve converter valor int para double', () {
        final map = {
          'id': 1,
          'origem': 'Teste',
          'valor': 100, // int em vez de double
          'pago': 0,
          'mes': 1,
          'ano': 2025,
          'createdAt': '2025-01-01T00:00:00.000Z',
        };

        final gasto = Gasto.fromMap(map);
        expect(gasto.valor, isA<double>());
        expect(gasto.valor, 100.0);
      });
    });

    group('toMap', () {
      test('deve converter Gasto para Map corretamente', () {
        final gasto = Gasto(
          id: 10,
          origem: 'Bradesco',
          valor: 500.25,
          pago: true,
          mes: 3,
          ano: 2025,
          createdAt: '2025-03-10T08:00:00.000Z',
        );

        final map = gasto.toMap();

        expect(map['id'], 10);
        expect(map['origem'], 'Bradesco');
        expect(map['valor'], 500.25);
        expect(map['pago'], 1); // true -> 1
        expect(map['mes'], 3);
        expect(map['ano'], 2025);
        expect(map['createdAt'], '2025-03-10T08:00:00.000Z');
      });

      test('deve converter pago false para 0', () {
        final gasto = Gasto(
          origem: 'Teste',
          valor: 100.0,
          pago: false,
          mes: 1,
          ano: 2025,
          createdAt: '2025-01-01T00:00:00.000Z',
        );

        final map = gasto.toMap();
        expect(map['pago'], 0);
      });

      test('não deve incluir id quando for null', () {
        final gasto = Gasto(
          origem: 'Teste',
          valor: 100.0,
          pago: false,
          mes: 1,
          ano: 2025,
          createdAt: '2025-01-01T00:00:00.000Z',
        );

        final map = gasto.toMap();
        expect(map.containsKey('id'), false);
      });
    });

    group('copyWith', () {
      test('deve criar cópia com campos alterados', () {
        final original = Gasto(
          id: 1,
          origem: 'Original',
          valor: 100.0,
          pago: false,
          mes: 1,
          ano: 2025,
          createdAt: '2025-01-01T00:00:00.000Z',
        );

        final copia = original.copyWith(
          origem: 'Alterado',
          pago: true,
        );

        expect(copia.id, 1); // não alterado
        expect(copia.origem, 'Alterado'); // alterado
        expect(copia.valor, 100.0); // não alterado
        expect(copia.pago, true); // alterado
        expect(copia.mes, 1); // não alterado
      });

      test('deve manter todos os valores se nenhum for passado', () {
        final original = Gasto(
          id: 5,
          origem: 'Teste',
          valor: 250.0,
          pago: true,
          mes: 6,
          ano: 2025,
          createdAt: '2025-06-01T00:00:00.000Z',
        );

        final copia = original.copyWith();

        expect(copia.id, original.id);
        expect(copia.origem, original.origem);
        expect(copia.valor, original.valor);
        expect(copia.pago, original.pago);
        expect(copia.mes, original.mes);
        expect(copia.ano, original.ano);
        expect(copia.createdAt, original.createdAt);
      });
    });

    group('toString', () {
      test('deve retornar string formatada corretamente', () {
        final gasto = Gasto(
          id: 1,
          origem: 'Teste',
          valor: 100.0,
          pago: false,
          mes: 12,
          ano: 2025,
          createdAt: '2025-12-01T00:00:00.000Z',
        );

        final str = gasto.toString();

        expect(str, contains('id: 1'));
        expect(str, contains('origem: Teste'));
        expect(str, contains('valor: 100.0'));
        expect(str, contains('pago: false'));
        expect(str, contains('mes: 12'));
        expect(str, contains('ano: 2025'));
      });
    });
  });
}
