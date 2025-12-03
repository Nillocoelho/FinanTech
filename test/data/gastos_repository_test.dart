import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:finantech/data/gastos_repository.dart';
import 'package:finantech/data/database_helper.dart';
import 'package:finantech/models/gasto.dart';

void main() {
  // Inicializa o sqflite para testes (em memória)
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('GastosRepository - Validação de Duplicados', () {
    late GastosRepository repository;

    setUp(() async {
      repository = GastosRepository();
      // Limpa o banco para cada teste
      final db = await DatabaseHelper().database;
      await db.delete(DatabaseHelper.tableGastos);
    });

    test('existeGastoComOrigem deve retornar false quando não existe', () async {
      final existe = await repository.existeGastoComOrigem('Santander', 12, 2025);
      expect(existe, false);
    });

    test('existeGastoComOrigem deve retornar true quando existe', () async {
      // Insere um gasto
      final gasto = Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto);

      // Verifica se existe
      final existe = await repository.existeGastoComOrigem('Santander', 12, 2025);
      expect(existe, true);
    });

    test('existeGastoComOrigem deve ser case-insensitive', () async {
      final gasto = Gasto(
        origem: 'SANTANDER',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto);

      // Verifica com diferentes cases
      expect(await repository.existeGastoComOrigem('santander', 12, 2025), true);
      expect(await repository.existeGastoComOrigem('Santander', 12, 2025), true);
      expect(await repository.existeGastoComOrigem('SANTANDER', 12, 2025), true);
      expect(await repository.existeGastoComOrigem('SaNtAnDeR', 12, 2025), true);
    });

    test('existeGastoComOrigem não deve encontrar em mês/ano diferente', () async {
      final gasto = Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto);

      // Verifica em outros períodos
      expect(await repository.existeGastoComOrigem('Santander', 11, 2025), false);
      expect(await repository.existeGastoComOrigem('Santander', 12, 2024), false);
      expect(await repository.existeGastoComOrigem('Santander', 1, 2026), false);
    });

    test('existeGastoComOrigem deve excluir um ID específico', () async {
      final gasto = Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await repository.insertGasto(gasto);

      // Verifica excluindo o próprio ID (útil para edição)
      final existeExcluindoId = await repository.existeGastoComOrigem(
        'Santander', 12, 2025, excludeId: id);
      expect(existeExcluindoId, false);

      // Verifica sem excluir
      final existeSemExcluir = await repository.existeGastoComOrigem(
        'Santander', 12, 2025);
      expect(existeSemExcluir, true);
    });

    test('existeGastoComOrigem com excludeId deve encontrar outros registros', () async {
      // Insere dois gastos
      final gasto1 = Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id1 = await repository.insertGasto(gasto1);

      final gasto2 = Gasto(
        origem: 'Santander', // Mesmo nome
        valor: 200.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto2);

      // Verifica excluindo apenas o primeiro ID - deve encontrar o segundo
      final existe = await repository.existeGastoComOrigem(
        'Santander', 12, 2025, excludeId: id1);
      expect(existe, true);
    });

    test('existeGastoComOrigem deve tratar espaços em branco', () async {
      final gasto = Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto);

      // Verifica com espaços extras (devem ser tratados)
      final existe = await repository.existeGastoComOrigem('  Santander  ', 12, 2025);
      // O método faz trim(), então deve encontrar
      expect(existe, true);
    });
  });

  group('GastosRepository - CRUD básico', () {
    late GastosRepository repository;

    setUp(() async {
      repository = GastosRepository();
      final db = await DatabaseHelper().database;
      await db.delete(DatabaseHelper.tableGastos);
    });

    test('insertGasto deve inserir e retornar ID', () async {
      final gasto = Gasto(
        origem: 'Teste',
        valor: 150.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );

      final id = await repository.insertGasto(gasto);
      expect(id, greaterThan(0));
    });

    test('getGastosDoMes deve retornar lista de gastos', () async {
      final gasto = Gasto(
        origem: 'Teste',
        valor: 150.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      await repository.insertGasto(gasto);

      final gastos = await repository.getGastosDoMes(12, 2025);
      expect(gastos.length, 1);
      expect(gastos.first.origem, 'Teste');
    });

    test('atualizarPago deve atualizar status de pagamento', () async {
      final gasto = Gasto(
        origem: 'Teste',
        valor: 150.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await repository.insertGasto(gasto);

      await repository.atualizarPago(id, true);

      final gastos = await repository.getGastosDoMes(12, 2025);
      expect(gastos.first.pago, true);
    });

    test('deleteGasto deve remover o gasto', () async {
      final gasto = Gasto(
        origem: 'Teste',
        valor: 150.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      );
      final id = await repository.insertGasto(gasto);

      await repository.deleteGasto(id);

      final gastos = await repository.getGastosDoMes(12, 2025);
      expect(gastos.isEmpty, true);
    });

    test('getTotalDoMes deve somar apenas gastos não pagos', () async {
      await repository.insertGasto(Gasto(
        origem: 'Gasto 1',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await repository.insertGasto(Gasto(
        origem: 'Gasto 2',
        valor: 200.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await repository.insertGasto(Gasto(
        origem: 'Gasto Pago',
        valor: 500.0,
        pago: true,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));

      final total = await repository.getTotalDoMes(12, 2025);
      expect(total, 300.0); // 100 + 200, não inclui o pago
    });

    test('getOrigensDistintas deve retornar origens únicas', () async {
      await repository.insertGasto(Gasto(
        origem: 'Santander',
        valor: 100.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await repository.insertGasto(Gasto(
        origem: 'Inter',
        valor: 200.0,
        pago: false,
        mes: 12,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));
      await repository.insertGasto(Gasto(
        origem: 'Santander', // Duplicada
        valor: 300.0,
        pago: false,
        mes: 11,
        ano: 2025,
        createdAt: DateTime.now().toIso8601String(),
      ));

      final origens = await repository.getOrigensDistintas();
      expect(origens.length, 2);
      expect(origens, containsAll(['Inter', 'Santander']));
    });
  });
}
