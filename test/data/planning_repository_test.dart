import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finantech/data/database_helper.dart';
import 'package:finantech/data/gastos_repository.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final repo = GastosRepository();
  final now = DateTime(2026, 1, 1);
  Gasto base({
    String name = 'Internet',
    double value = 100,
    int month = 1,
    int day = 31,
    String category = 'Moradia',
  }) => Gasto(
    origem: name,
    valor: value,
    pago: false,
    mes: month,
    ano: 2026,
    createdAt: now.toIso8601String(),
    vencimento: DateTime(2026, month, day),
    categoria: category,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp(
      'finantech-planning-test-',
    );
    await databaseFactory.setDatabasesPath(directory.path);
  });
  setUp(() async {
    final db = await DatabaseHelper().database;
    await db.delete('gastos');
    await db.delete('recorrencias');
  });
  tearDownAll(() async {
    await DatabaseHelper().close();
    // This directory is created exclusively for this test suite.
    await directory.delete(recursive: true);
  });

  for (final version in [1, 2]) {
    test('migrates schema v$version without changing existing financial data', () async {
      await DatabaseHelper().close();
      final path = '${directory.path}/finantech.db';
      await databaseFactory.deleteDatabase(path);
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE gastos (id INTEGER PRIMARY KEY AUTOINCREMENT, origem TEXT NOT NULL, valor REAL NOT NULL, pago INTEGER NOT NULL, mes INTEGER NOT NULL, ano INTEGER NOT NULL, createdAt TEXT NOT NULL${version == 2 ? ', vencimento TEXT' : ''})',
            );
          },
        ),
      );
      await legacy.insert('gastos', {
        'id': 9,
        'origem': 'Conta antiga',
        'valor': 149.99,
        'pago': 1,
        'mes': 12,
        'ano': 2025,
        'createdAt': '2025-12-01',
      });
      await legacy.close();
      final db = await DatabaseHelper().database;
      expect(await db.getVersion(), 3);
      final row = (await repo.getGastosDoMes(12, 2025)).single;
      expect(row.id, 9);
      expect(row.valor, 149.99);
      expect(row.pago, isTrue);
      expect(row.categoria, 'Sem categoria');
      expect(row.parcelaGrupo, isNull);
      expect(await db.query('recorrencias'), isEmpty);
    });
  }

  test(
    'manual merging respects category and never absorbs an installment',
    () async {
      await repo.criarParcelamento(base(), 2);
      await repo.salvarSomandoSeExistir(base(category: 'Educação'));
      await repo.salvarSomandoSeExistir(base(category: 'Moradia', value: 10));
      await repo.salvarSomandoSeExistir(base(category: 'Moradia', value: 5));
      final rows = await repo.getGastosDoMes(1, 2026);
      expect(rows.length, 3);
      expect(rows.singleWhere((g) => g.parcelado).valor, 50);
      expect(
        rows.singleWhere((g) => !g.parcelado && g.categoria == 'Moradia').valor,
        15,
      );
    },
  );

  test(
    'independent installment groups preserve cents and month-end dates',
    () async {
      await repo.criarParcelamento(base(value: 100), 3);
      await repo.criarParcelamento(base(value: 200), 2);
      final january = await repo.getGastosDoMes(1, 2026);
      expect(january.length, 2);
      expect(january.map((g) => g.parcelaGrupo).toSet().length, 2);
      final first = january.singleWhere((g) => g.parcelaTotal == 3);
      final parts = await repo.getParcelas(first.parcelaGrupo!);
      expect(parts.map((g) => g.parcelaNumero), [1, 2, 3]);
      expect(
        parts.fold<double>(0, (sum, g) => sum + g.valor),
        closeTo(100, 0.00001),
      );
      expect(parts[1].vencimento, DateTime(2026, 2, 28));
      expect(parts[2].vencimento, DateTime(2026, 3, 31));
      await repo.atualizarPago(parts.first.id!, true);
      final updated = await repo.getParcelas(first.parcelaGrupo!);
      expect(updated.where((g) => !g.pago).length, 2);
    },
  );

  test('invalid installment plans do not write partial rows', () async {
    await expectLater(
      repo.criarParcelamento(base(value: 0.01), 3),
      throwsArgumentError,
    );
    expect(await repo.getGastosDoMes(1, 2026), isEmpty);
  });

  test(
    'recurrence is idempotent and preserves day 31 beyond February',
    () async {
      await repo.criarRecorrencia(base(), now: now);
      await repo.prepararMes(1, 2026, now: now);
      final db = await DatabaseHelper().database;
      expect((await db.query('gastos')).length, 12);
      expect(
        (await repo.getGastosDoMes(2, 2026)).single.vencimento,
        DateTime(2026, 2, 28),
      );
      expect(
        (await repo.getGastosDoMes(3, 2026)).single.vencimento,
        DateTime(2026, 3, 31),
      );
      final february = (await repo.getGastosDoMes(2, 2026)).single;
      await repo.deleteGasto(february.id!);
      await repo.prepararMes(3, 2026, now: now);
      expect(await repo.getGastosDoMes(2, 2026), isEmpty);
      await repo.prepararMes(1, 2028, now: now);
      expect(
        (await repo.getGastosDoMes(2, 2028)).single.vencimento,
        DateTime(2028, 2, 29),
      );
    },
  );

  test(
    'editing one occurrence does not change its rule or future months',
    () async {
      await repo.criarRecorrencia(base(), now: now);
      final january = (await repo.getGastosDoMes(1, 2026)).single;
      await repo.updateGasto(january.copyWith(valor: 150, categoria: 'Outros'));
      expect((await repo.getGastosDoMes(2, 2026)).single.valor, 100);
      expect(
        (await repo.getRecorrencia(january.recorrenciaId!))!.categoria,
        'Moradia',
      );
    },
  );

  test('series editing preserves past and paid occurrences, updating future generation', () async {
    await repo.criarRecorrencia(base(), now: now);
    final february = (await repo.getGastosDoMes(2, 2026)).single;
    final march = (await repo.getGastosDoMes(3, 2026)).single;
    await repo.atualizarPago(march.id!, true);
    await repo.atualizarRecorrencia(
      february.recorrenciaId!,
      february.copyWith(
        valor: 120,
        categoria: 'Assinaturas',
        vencimento: DateTime(2026, 2, 10),
      ),
    );
    expect((await repo.getGastosDoMes(1, 2026)).single.valor, 100);
    expect((await repo.getGastosDoMes(2, 2026)).single.valor, 120);
    expect((await repo.getGastosDoMes(3, 2026)).single.valor, 100);
    expect(
      (await repo.getGastosDoMes(4, 2026)).single.vencimento,
      DateTime(2026, 4, 10),
    );
    await repo.prepararMes(1, 2027, now: now);
    final next = (await repo.getGastosDoMes(1, 2027)).single;
    expect(next.valor, 120);
    expect(next.categoria, 'Assinaturas');
    expect(next.vencimento, DateTime(2027, 1, 10));
  });

  test(
    'stopping recurrence preserves history and paid future entries',
    () async {
      await repo.criarRecorrencia(base(), now: now);
      final march = (await repo.getGastosDoMes(3, 2026)).single;
      final april = (await repo.getGastosDoMes(4, 2026)).single;
      await repo.atualizarPago(april.id!, true);
      await repo.encerrarRecorrencia(march.recorrenciaId!, 3, 2026);
      await repo.prepararMes(1, 2028, now: now);
      expect((await repo.getGastosDoMes(3, 2026)).length, 1);
      expect(
        (await repo.getGastosDoMes(3, 2026)).single.recorrenciaAtiva,
        isFalse,
      );
      expect((await repo.getGastosDoMes(4, 2026)).single.pago, isTrue);
      expect(await repo.getGastosDoMes(5, 2026), isEmpty);
      expect(await repo.getGastosDoMes(1, 2028), isEmpty);
      expect((await repo.getRecorrencia(march.recorrenciaId!))!.ativo, isFalse);
    },
  );

  test(
    'future commitments combine open recurring bills and installments only',
    () async {
      await repo.criarParcelamento(base(value: 120), 3);
      await repo.criarRecorrencia(base(value: 10), now: now);
      await repo.insertGasto(
        base(name: 'Avulso', value: 999, month: 2, day: 10),
      );
      var totals = await repo.getCompromissosFuturos(1, 2026);
      expect(totals[DateTime(2026, 2)], 50);
      expect(totals[DateTime(2026, 3)], 50);
      expect(totals[DateTime(2026, 4)], 10);
      final part = (await repo.getGastosDoMes(
        2,
        2026,
      )).singleWhere((g) => g.parcelado);
      await repo.atualizarPago(part.id!, true);
      totals = await repo.getCompromissosFuturos(1, 2026);
      expect(totals[DateTime(2026, 2)], 10);
    },
  );

  test(
    'full backup restores categories, installment groups and recurrence cursor',
    () async {
      await repo.criarParcelamento(base(), 3);
      await repo.criarRecorrencia(base(name: 'Aluguel'), now: now);
      final db = await DatabaseHelper().database;
      final recurring = (await repo.getGastosDoMes(
        2,
        2026,
      )).singleWhere((g) => g.recorrenciaId != null);
      await repo.deleteGasto(recurring.id!);
      final service = BackupService(directoryProvider: () async => directory);
      final path = await service.criarBackup();
      final backup = BackupService.decodeDocument(
        await File(path).readAsString(),
      );
      final before = await db.query('gastos', orderBy: 'id');
      await db.delete('gastos');
      await db.delete('recorrencias');
      await service.restaurar(backup.gastos, recorrencias: backup.recorrencias);
      expect(await db.query('gastos', orderBy: 'id'), before);
      await repo.prepararMes(1, 2026, now: now);
      expect(
        (await repo.getGastosDoMes(
          2,
          2026,
        )).where((g) => g.recorrenciaId != null),
        isEmpty,
      );
      expect((await service.listarBackupsLocais()).length, 2);
    },
  );

  test(
    'legacy backup remains readable and corrupt planning metadata is rejected',
    () {
      final row = base().copyWith(id: 1).toMap()..remove('categoria');
      final old = jsonEncode({
        'app': 'FinanTech',
        'version': 1,
        'gastos': [row],
      });
      expect(BackupService.decode(old).single.categoria, 'Sem categoria');
      for (final change in <Map<String, dynamic>>[
        {'parcelaGrupo': 'group', 'parcelaTotal': 3, 'parcelaNumero': 4},
        {'parcelaGrupo': 'group', 'parcelaTotal': 3, 'parcelaNumero': 1.0},
        {'parcelaNumero': 1},
        {'categoria': 123},
        {'recorrenciaId': 'missing'},
      ]) {
        final content = jsonEncode({
          'app': 'FinanTech',
          'version': 2,
          'gastos': [
            {...row, ...change},
          ],
          'recorrencias': [],
        });
        expect(
          () => BackupService.decodeDocument(content),
          throwsFormatException,
        );
      }
    },
  );
}
