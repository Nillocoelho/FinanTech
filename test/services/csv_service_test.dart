import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finantech/data/database_helper.dart';
import 'package:finantech/data/gastos_repository.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/services/backup_service.dart';
import 'package:finantech/services/csv_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CsvService csv;
  final repo = GastosRepository();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('diazen-csv-test-');
    await databaseFactory.setDatabasesPath(directory.path);
  });
  setUp(() async {
    final db = await DatabaseHelper().database;
    await db.delete('gastos');
    await db.delete('recorrencias');
    csv = CsvService(
      backupService: BackupService(directoryProvider: () async => directory),
      directoryProvider: () async => directory,
    );
  });
  tearDownAll(() async {
    await DatabaseHelper().close();
    await directory.delete(recursive: true);
  });

  Gasto gasto(String origem, double valor, int mes, int ano, {bool pago = false}) =>
      Gasto(
        origem: origem,
        valor: valor,
        pago: pago,
        mes: mes,
        ano: ano,
        createdAt: '2026-01-01T00:00:00',
      );

  String planilha(List<String> linhas) => [
    ',,Diazen - Gastos Mensais',
    ',,A quem:,Abril,Maio,Junho,Julho,Agosto,Setembro,Outubro,Novembro,Dezembro,Janeiro,Fevereiro,Março,Abril',
    ...linhas,
  ].join('\r\n');

  Future<List<Map<String, Object?>>> linhas() async =>
      (await DatabaseHelper().database).query(
        'gastos',
        orderBy: 'ano, mes, origem',
      );

  test('export keeps April of both years apart and has a neutral title', () async {
    await repo.insertGasto(gasto('Aluguel', 1000, 4, 2026));
    await repo.insertGasto(gasto('Aluguel', 1000, 4, 2027));
    await repo.insertGasto(gasto('Aluguel', 50, 5, 2026, pago: true));
    await repo.insertGasto(gasto('Loja "A", Centro', 12.5, 1, 2027));
    final conteudo = await csv.gerarCsv(anoInicio: 2026);
    expect(conteudo, isNot(contains('Danillo')));
    expect(conteudo, contains(CsvService.titulo));
    final aluguel = conteudo
        .split('\n')
        .firstWhere((l) => l.startsWith(',,Aluguel'));
    expect(
      aluguel,
      ',,Aluguel,"1000,00",0,0,0,0,0,0,0,0,0,0,0,"1000,00"',
    );
    expect(conteudo, contains(',,"Loja ""A"", Centro",'));
    expect(conteudo, contains(',,Total,"1000,00",'));
  });

  test('export -> import round trip is idempotent', () async {
    await repo.insertGasto(gasto('Aluguel', 1000, 4, 2026));
    await repo.insertGasto(gasto('Aluguel', 1000, 4, 2027));
    await repo.insertGasto(gasto('Loja "A", Centro', 1234.56, 1, 2027));
    await repo.criarParcelamento(
      gasto('Notebook', 300, 5, 2026).copyWith(vencimento: DateTime(2026, 5, 10)),
      3,
    );
    final antes = await linhas();
    final conteudo = await csv.gerarCsv(anoInicio: 2026);

    final resultado = await csv.importarDeCsv(conteudo, anoInicio: 2026);
    expect(resultado.importados, 0);
    expect(resultado.rejeitados, 0);
    expect(resultado.inalterados, greaterThan(0));
    expect(await linhas(), antes);

    // Banco vazio: a importação recria os valores, e a segunda não dobra.
    final db = await DatabaseHelper().database;
    await db.delete('gastos');
    final primeira = await csv.importarDeCsv(conteudo, anoInicio: 2026);
    expect(primeira.importados, 6);
    final segunda = await csv.importarDeCsv(conteudo, anoInicio: 2026);
    expect(segunda.importados, 0);
    final abril = await repo.getGastosDoMes(4, 2027);
    expect(abril.single.valorCentavos, 100000);
    final loja = await repo.getGastosDoMes(1, 2027);
    expect(loja.single.origem, 'Loja "A", Centro');
    expect(loja.single.valorCentavos, 123456);
  });

  test('import replaces the month value instead of summing', () async {
    await repo.insertGasto(gasto('Mercado', 300, 6, 2026));
    final resultado = await csv.importarDeCsv(
      planilha([',,Mercado,,,450']),
      anoInicio: 2026,
    );
    expect(resultado.importados, 1);
    expect((await repo.getGastosDoMes(6, 2026)).single.valor, 450);
  });

  test('origins containing "total" are imported; only the Total row stops', () async {
    final resultado = await csv.importarDeCsv(
      planilha([
        ',,TotalPass,"1.234,56"',
        ',,Seguro Total,R\$ 50,00',
        ',,Total,"1.284,56"',
        ',,Depois do total,99',
      ]),
      anoInicio: 2026,
    );
    expect(resultado.importados, 2);
    final abril = await repo.getGastosDoMes(4, 2026);
    expect(
      {for (final g in abril) g.origem: g.valorCentavos},
      {'TotalPass': 123456, 'Seguro Total': 5000},
    );
  });

  test('thousands separators, currency symbols and invalid cells', () async {
    final resultado = await csv.importarDeCsv(
      planilha([',,Cartão,"1.234,56","R\$ 50,00",abc,"12,345",0,']),
      anoInicio: 2026,
    );
    expect(resultado.importados, 2);
    expect(resultado.rejeitados, 2);
    expect(resultado.rejeitadas.first, contains('Cartão (Junho/2026)'));
    expect(resultado.mensagem, contains('2 células ignoradas'));
    expect((await repo.getGastosDoMes(4, 2026)).single.valorCentavos, 123456);
    expect((await repo.getGastosDoMes(5, 2026)).single.valorCentavos, 5000);
  });

  test('months wrap to the next year and unknown months are rejected', () async {
    await csv.importarDeCsv(
      planilha([',,Escola,,,,,,,,,,"10,00",,,"20,00"']),
      anoInicio: 2026,
    );
    expect((await repo.getGastosDoMes(1, 2027)).single.valor, 10);
    expect((await repo.getGastosDoMes(4, 2027)).single.valor, 20);
    expect(await repo.getGastosDoMes(4, 2026), isEmpty);

    await expectLater(
      csv.importarDeCsv(',,A quem:,Abril,Mar�o\n,,X,1,2', anoInicio: 2026),
      throwsFormatException,
    );
    expect(await repo.getGastosDoMes(3, 2027), isEmpty);
  });

  test('Latin-1 files are decoded and accents survive', () {
    final bytes = latin1.encode(',,A quem:,Março\n,,Pão,1');
    expect(CsvService.decodificar(bytes), contains('Março'));
    expect(CsvService.decodificar(utf8.encode('﻿Açaí')), 'Açaí');
  });

  test('import creates a backup first and writes atomically', () async {
    await repo.insertGasto(gasto('Antes', 10, 4, 2026));
    final pasta = await Directory('${directory.path}/import').create();
    final backups = BackupService(directoryProvider: () async => pasta);
    csv = CsvService(backupService: backups);
    await csv.importarDeCsv(planilha([',,Novo,5']), anoInicio: 2026);
    final copias = await backups.listarBackupsLocais();
    expect(copias.length, 1);
    final copia = BackupService.decode(await copias.single.readAsString());
    expect(copia.map((g) => g.origem), ['Antes']);

    final db = await DatabaseHelper().database;
    await db.execute(
      "CREATE TRIGGER falha_csv BEFORE INSERT ON gastos WHEN NEW.origem = 'Quebra' "
      "BEGIN SELECT RAISE(ABORT, 'falha simulada'); END",
    );
    addTearDown(() => db.execute('DROP TRIGGER IF EXISTS falha_csv'));
    final estado = await linhas();
    await expectLater(
      csv.importarDeCsv(
        planilha([',,Primeiro,7', ',,Quebra,8']),
        anoInicio: 2026,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await linhas(), estado);
  });
}
