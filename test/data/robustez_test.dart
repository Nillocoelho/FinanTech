import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finantech/data/database_helper.dart';
import 'package:finantech/data/gastos_repository.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/services/backup_service.dart';
import 'package:finantech/utils/currency_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final repo = GastosRepository();
  final now = DateTime(2026, 1, 15);

  Gasto base({
    String name = 'Mercado',
    double value = 300,
    int month = 11,
    int year = 2026,
    bool pago = false,
  }) => Gasto(
    origem: name,
    valor: value,
    pago: pago,
    mes: month,
    ano: year,
    createdAt: '2026-01-01T00:00:00',
    vencimento: DateTime(year, month, 10),
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('diazen-robustez-test-');
    await databaseFactory.setDatabasesPath(directory.path);
  });
  setUp(() async {
    final db = await DatabaseHelper().database;
    await db.delete('gastos');
    await db.delete('recorrencias');
  });
  tearDownAll(() async {
    await DatabaseHelper().close();
    await directory.delete(recursive: true);
  });

  test('adding to a paid entry inserts a new open one and keeps the payment', () async {
    final pagoId = await repo.insertGasto(base(pago: true));
    final resultado = await repo.salvarSomandoSeExistir(base(value: 50));
    expect(resultado.somado, isFalse);
    final rows = await repo.getGastosDoMes(11, 2026);
    expect(rows.length, 2);
    final pago = rows.singleWhere((g) => g.id == pagoId);
    expect(pago.pago, isTrue);
    expect(pago.valor, 300);
    expect(rows.singleWhere((g) => !g.pago).valor, 50);

    // Em aberto, continua somando.
    final soma = await repo.salvarSomandoSeExistir(base(value: 25));
    expect(soma.somado, isTrue);
    expect(soma.gasto.valorCentavos, 7500);
  });

  test('cents avoid floating point drift', () async {
    await repo.insertGasto(base(value: 0.1));
    await repo.salvarSomandoSeExistir(base(value: 0.2));
    final g = (await repo.getGastosDoMes(11, 2026)).single;
    expect(g.valorCentavos, 30);
    expect(g.valor, 0.3);
    expect(await repo.getTotalDoMes(11, 2026), 0.3);
  });

  test('inserts abort instead of replacing a row on a unique key', () async {
    await repo.criarParcelamento(base(), 2);
    final parte = (await repo.getGastosDoMes(11, 2026)).single;
    await repo.atualizarPago(parte.id!, true);
    await expectLater(
      repo.insertGasto(parte.copyWith(pago: false, id: 999)),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.getParcelas(parte.parcelaGrupo!)).first.pago, isTrue);
  });

  test('repository emits change events instead of syncing reminders', () async {
    var eventos = 0;
    final sub = GastosRepository.changes.listen((_) => eventos++);
    addTearDown(sub.cancel);
    final id = await repo.insertGasto(base());
    await repo.atualizarPago(id, true);
    await repo.deleteGasto(id);
    await Future<void>.delayed(Duration.zero);
    expect(eventos, 3);
  });

  test('distant months are projected, not written, and act like real rows', () async {
    await repo.criarRecorrencia(base(name: 'Aluguel', month: 1), now: now);
    final db = await DatabaseHelper().database;
    expect((await db.query('gastos')).length, 12);

    await repo.prepararMes(1, 2090, now: now);
    expect((await db.query('gastos')).length, 12);
    final distante = (await repo.getGastosDoMes(6, 2030)).single;
    expect(distante.projetado, isTrue);
    expect(distante.vencimento, DateTime(2030, 6, 10));
    expect(
      (await repo.getCompromissosFuturos(5, 2030))[DateTime(2030, 6)],
      300,
    );

    await repo.atualizarPago(distante.id!, true);
    final gravado = (await repo.getGastosDoMes(6, 2030)).single;
    expect(gravado.projetado, isFalse);
    expect(gravado.pago, isTrue);
    // Os meses intermediários foram gravados para manter o cursor coerente.
    expect((await repo.getGastosDoMes(5, 2030)).single.projetado, isFalse);
    expect((await repo.getGastosDoMes(7, 2030)).single.projetado, isTrue);

    final julho = (await repo.getGastosDoMes(7, 2030)).single;
    await repo.deleteGasto(julho.id!);
    await repo.prepararMes(7, 2030, now: now);
    expect(await repo.getGastosDoMes(7, 2030), isEmpty);
  });

  test('restore is atomic: a failure mid-way keeps the current data', () async {
    await repo.insertGasto(base(name: 'Atual'));
    final db = await DatabaseHelper().database;
    final antes = await db.query('gastos');
    final service = BackupService(directoryProvider: () async => directory);
    await db.execute(
      "CREATE TRIGGER falha_restauracao BEFORE INSERT ON gastos WHEN NEW.origem = 'Quebra' "
      "BEGIN SELECT RAISE(ABORT, 'falha simulada'); END",
    );
    addTearDown(() => db.execute('DROP TRIGGER IF EXISTS falha_restauracao'));
    await expectLater(
      service.restaurar([
        base(name: 'Novo 1').copyWith(id: 1),
        base(name: 'Quebra').copyWith(id: 2),
      ]),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('gastos'), antes);
  });

  test('backups created before cents still restore, and rotation keeps 10', () async {
    final legado = jsonEncode({
      'app': 'FinanTech',
      'version': 1,
      'gastos': [
        {
          'id': 1,
          'origem': 'Antigo',
          'valor': 149.99,
          'pago': 0,
          'mes': 3,
          'ano': 2025,
          'createdAt': '2025-03-01',
        },
      ],
    });
    final pasta = await Directory('${directory.path}/rotacao').create();
    await File('${pasta.path}/finantech_backup_1.json').writeAsString(legado);
    final service = BackupService(directoryProvider: () async => pasta);
    final doc = BackupService.decodeDocument(legado);
    expect(doc.gastos.single.valorCentavos, 14999);
    await service.restaurar(doc.gastos);
    expect((await repo.getGastosDoMes(3, 2025)).single.valorCentavos, 14999);

    for (var i = 0; i < 12; i++) {
      await service.criarBackup();
    }
    final arquivos = await service.listarBackupsLocais();
    expect(arquivos.length, BackupService.maxBackupsLocais);
    expect(
      arquivos.every((f) => f.path.contains(BackupService.prefixo)),
      isTrue,
    );
  });

  test('currency parsing and the 11-digit input limit', () {
    expect(CurrencyHelper.parseCentavos('1.234,56'), 123456);
    expect(CurrencyHelper.parseCentavos('R\$ 50,00'), 5000);
    expect(CurrencyHelper.parseCentavos('1234.5'), 123450);
    expect(CurrencyHelper.parseCentavos('12,345'), isNull);
    expect(CurrencyHelper.formatCentavos(123456789), '1.234.567,89');
    final formatter = CurrencyInputFormatter();
    const anterior = TextEditingValue(text: '1,00');
    final colado = formatter.formatEditUpdate(
      anterior,
      const TextEditingValue(text: '12345678901234567890'),
    );
    expect(colado, anterior);
    expect(
      formatter
          .formatEditUpdate(anterior, const TextEditingValue(text: '99999999999'))
          .text,
      '999.999.999,99',
    );
  });
}
