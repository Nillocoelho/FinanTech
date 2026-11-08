import '../services/notification_service.dart';

import 'dart:math';

import '../models/recurring_expense.dart';
import '../utils/installment_helper.dart';

import 'package:sqflite/sqflite.dart';

import '../models/gasto.dart';
import 'database_helper.dart';

/// Repositório responsável por todas as operações de CRUD na tabela de gastos.
///
/// Esta classe abstrai a lógica de acesso ao banco de dados, fornecendo
/// métodos de alto nível para manipular os gastos.
class GastosRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  /// Insere um novo gasto no banco de dados
  ///
  /// Recebe um objeto [Gasto] e o persiste no SQLite.
  /// O campo 'id' será gerado automaticamente pelo banco.
  Future<int> insertGasto(Gasto gasto) async {
    final db = await _databaseHelper.database;

    final result = await db.insert(
      DatabaseHelper.tableGastos,
      gasto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await NotificationService().refreshAfterChange();
    return result;
  }

  /// Retorna todos os gastos de um mês/ano específico
  ///
  /// Os gastos são ordenados pela data de criação (mais recentes primeiro).
  Future<List<Gasto>> getGastosDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;

    final maps = await db.rawQuery('''SELECT gastos.*, recorrencias.ativo AS recorrenciaAtiva
      FROM gastos LEFT JOIN recorrencias ON gastos.recorrenciaId = recorrencias.id
      WHERE gastos.mes = ? AND gastos.ano = ? ORDER BY gastos.createdAt DESC''', [mes, ano]);

    // Converte a lista de Maps para lista de objetos Gasto
    return List.generate(maps.length, (index) {
      return Gasto.fromMap(maps[index]);
    });
  }

  /// Atualiza o status de pagamento de um gasto
  ///
  /// [id] é o identificador do gasto a ser atualizado.
  /// [pago] indica se o gasto foi pago (true) ou não (false).
  Future<int> atualizarPago(int id, bool pago) async {
    final db = await _databaseHelper.database;

    final result = await db.update(
      DatabaseHelper.tableGastos,
      {'pago': pago ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await NotificationService().refreshAfterChange();
    return result;
  }

  /// Calcula o total de gastos não pagos de um mês/ano
  ///
  /// Soma todos os valores onde 'pago = 0' para o mês/ano especificado.
  /// Retorna 0.0 se não houver gastos ou se todos estiverem pagos.
  Future<double> getTotalDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(valor), 0.0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
    ''',
      [mes, ano],
    );

    // COALESCE garante que retorna 0.0 se não houver registros
    return (result.first['total'] as num).toDouble();
  }

  /// Retorna um mapa com o total de gastos não pagos por origem
  ///
  /// A chave do mapa é o nome da origem, e o valor é a soma dos gastos
  /// não pagos para aquela origem no mês/ano especificado.
  ///
  /// Exemplo de retorno: {'Santander': 1500.00, 'Inter': 800.50}
  Future<Map<String, double>> getTotaisPorOrigemDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT origem, COALESCE(SUM(valor), 0.0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
      GROUP BY origem
      ORDER BY total DESC
    ''',
      [mes, ano],
    );

    // Converte o resultado para um Map<String, double>
    final Map<String, double> totais = {};
    for (final row in result) {
      final origem = row['origem'] as String;
      final total = (row['total'] as num).toDouble();
      totais[origem] = total;
    }

    return totais;
  }

  /// Exclui um gasto pelo ID
  ///
  /// Retorna o número de linhas afetadas (1 se excluído com sucesso, 0 se não encontrado).
  Future<int> deleteGasto(int id) async {
    final db = await _databaseHelper.database;

    final result = await db.delete(
      DatabaseHelper.tableGastos,
      where: 'id = ?',
      whereArgs: [id],
    );
    await NotificationService().refreshAfterChange();
    return result;
  }

  /// Atualiza um gasto existente
  ///
  /// [gasto] deve conter o id do gasto a ser atualizado.
  /// Retorna o número de linhas afetadas.
  Future<int> updateGasto(Gasto gasto) async {
    final db = await _databaseHelper.database;

    final result = await db.update(
      DatabaseHelper.tableGastos,
      gasto.toMap(),
      where: 'id = ?',
      whereArgs: [gasto.id],
    );
    await NotificationService().refreshAfterChange();
    return result;
  }

  /// Busca um gasto pela origem em um mês/ano específico.
  ///
  /// Quando houver mais de um registro correspondente, retorna o mais recente.
  Future<Gasto?> getGastoComOrigem(
    String origem,
    int mes,
    int ano, {
    int? excludeId,
  }) async {
    final db = await _databaseHelper.database;

    String query =
        '''
      SELECT *
      FROM ${DatabaseHelper.tableGastos}
      WHERE LOWER(origem) = LOWER(?) AND mes = ? AND ano = ?
    ''';
    final args = <dynamic>[origem.trim(), mes, ano];

    if (excludeId != null) {
      query += ' AND id != ?';
      args.add(excludeId);
    }

    query += ' ORDER BY createdAt DESC, id DESC LIMIT 1';

    final result = await db.rawQuery(query, args);
    if (result.isEmpty) {
      return null;
    }

    return Gasto.fromMap(result.first);
  }

  /// Insere um novo gasto ou soma seu valor a um gasto existente da mesma origem/mês/ano.
  ///
  /// Retorna `somado = true` quando um registro existente foi atualizado.
  Future<({bool somado, Gasto gasto})> salvarSomandoSeExistir(
    Gasto gasto,
  ) async {
    final db = await _databaseHelper.database;
    final matches = await db.query(
      DatabaseHelper.tableGastos,
      where: 'LOWER(origem) = LOWER(?) AND mes = ? AND ano = ? AND categoria = ? AND parcelaGrupo IS NULL AND recorrenciaId IS NULL',
      whereArgs: [gasto.origem.trim(), gasto.mes, gasto.ano, gasto.categoria],
      orderBy: 'createdAt DESC, id DESC',
      limit: 1,
    );
    final gastoExistente = matches.isEmpty
        ? null
        : Gasto.fromMap(matches.single);

    if (gastoExistente == null) {
      final id = await insertGasto(gasto);
      return (somado: false, gasto: gasto.copyWith(id: id));
    }

    final gastoAtualizado = gastoExistente.copyWith(
      valor: gastoExistente.valor + gasto.valor,
      vencimento: gasto.vencimento,
      pago: false,
    );
    await updateGasto(gastoAtualizado);
    return (somado: true, gasto: gastoAtualizado);
  }

  /// Retorna a lista de todas as origens distintas já cadastradas
  ///
  /// Útil para sugestões de autocompletar no campo de origem.
  Future<List<String>> getOrigensDistintas() async {
    final db = await _databaseHelper.database;

    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT DISTINCT origem FROM ${DatabaseHelper.tableGastos}
      ORDER BY origem ASC
    ''');

    return result.map((row) => row['origem'] as String).toList();
  }

  /// Verifica se já existe um gasto com a mesma origem no mês/ano especificado
  ///
  /// [origem] é o nome da origem a verificar (case-insensitive)
  /// [mes] e [ano] especificam o período
  /// [excludeId] opcional para excluir um gasto específico (útil na edição)
  /// Retorna true se já existe, false caso contrário
  Future<bool> existeGastoComOrigem(
    String origem,
    int mes,
    int ano, {
    int? excludeId,
  }) async {
    final gasto = await getGastoComOrigem(
      origem,
      mes,
      ano,
      excludeId: excludeId,
    );
    return gasto != null;
  }

  /// Retorna estatísticas gerais de um mês/ano
  ///
  /// Retorna um Map com:
  /// - 'totalEmAberto': soma de todos os gastos não pagos
  /// - 'totalPago': soma de todos os gastos pagos
  /// - 'quantidadeEmAberto': número de gastos não pagos
  /// - 'quantidadePaga': número de gastos pagos
  Future<Map<String, dynamic>> getEstatisticasDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;

    final result = await db.rawQuery(
      '''
      SELECT 
        COALESCE(SUM(CASE WHEN pago = 0 THEN valor ELSE 0 END), 0.0) as totalEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN valor ELSE 0 END), 0.0) as totalPago,
        COALESCE(SUM(CASE WHEN pago = 0 THEN 1 ELSE 0 END), 0) as quantidadeEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN 1 ELSE 0 END), 0) as quantidadePaga
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ?
    ''',
      [mes, ano],
    );

    final row = result.first;
    return {
      'totalEmAberto': (row['totalEmAberto'] as num).toDouble(),
      'totalPago': (row['totalPago'] as num).toDouble(),
      'quantidadeEmAberto': (row['quantidadeEmAberto'] as num).toInt(),
      'quantidadePaga': (row['quantidadePaga'] as num).toInt(),
    };
  }

  String _seriesId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${List.generate(4, (_) => Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0')).join()}';

  Future<void> criarParcelamento(Gasto base, int quantidade) async {
    if (quantidade < 2 ||
        quantidade > 120 ||
        !base.valor.isFinite ||
        (base.valor * 100).round() < quantidade ||
        base.vencimento == null) {
      throw ArgumentError('Invalid installment plan');
    }
    final group = _seriesId();
    final values = InstallmentHelper.splitAmount(base.valor, quantidade);
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < quantidade; i++) {
        final period = InstallmentHelper.addMonths(base.mes, base.ano, i);
        final due = base.vencimento!;
        final lastDay = DateTime(due.year, due.month + i + 1, 0).day;
        batch.insert(
          DatabaseHelper.tableGastos,
          Gasto(
            origem: base.origem,
            valor: values[i],
            pago: false,
            mes: period.mes,
            ano: period.ano,
            createdAt: base.createdAt,
            categoria: base.categoria,
            parcelaGrupo: group,
            parcelaNumero: i + 1,
            parcelaTotal: quantidade,
            vencimento: DateTime(
              due.year,
              due.month + i,
              due.day.clamp(1, lastDay),
            ),
          ).toMap(),
        );
      }
      await batch.commit(noResult: true);
    });
    await NotificationService().refreshAfterChange();
  }

  Future<List<Gasto>> getParcelas(String grupo) async {
    final db = await _databaseHelper.database;
    return (await db.query(
      DatabaseHelper.tableGastos,
      where: 'parcelaGrupo = ?',
      whereArgs: [grupo],
      orderBy: 'parcelaNumero',
    )).map(Gasto.fromMap).toList();
  }

  Future<void> criarRecorrencia(Gasto base, {DateTime? now}) async {
    if (base.vencimento == null || !base.valor.isFinite || base.valor <= 0) {
      throw ArgumentError('Invalid recurring expense');
    }
    final clock = now ?? DateTime.now();
    final start = monthIndex(base.ano, base.mes);
    final rule = RecurringExpense(
      id: _seriesId(),
      origem: base.origem,
      valor: base.valor,
      categoria: base.categoria,
      inicioMes: start,
      proximoMes: start,
      diaVencimento: base.vencimento!.day,
      deslocamentoVencimento:
          monthIndex(base.vencimento!.year, base.vencimento!.month) - start,
    );
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.insert(DatabaseHelper.tableRecorrencias, rule.toMap());
      await _materialize(
        txn,
        max(start, monthIndex(clock.year, clock.month)) + 11,
        clock,
      );
    });
    await NotificationService().refreshAfterChange();
  }

  Future<void> prepararMes(int mes, int ano, {DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final db = await _databaseHelper.database;
    final count = await db.transaction(
      (txn) => _materialize(
        txn,
        max(monthIndex(ano, mes), monthIndex(clock.year, clock.month)) + 11,
        clock,
      ),
    );
    if (count > 0) await NotificationService().refreshAfterChange();
  }

  Future<int> _materialize(Transaction txn, int through, DateTime now) async {
    final limit = min(through, monthIndex(2100, 12));
    final rules = (await txn.query(
      DatabaseHelper.tableRecorrencias,
      where: 'ativo = 1 AND proximoMes <= ?',
      whereArgs: [limit],
    )).map(RecurringExpense.fromMap).toList();
    var count = 0;
    for (final rule in rules) {
      for (var index = rule.proximoMes; index <= limit; index++) {
        await txn.insert(
          DatabaseHelper.tableGastos,
          rule.occurrence(index, now).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count++;
      }
      // A cursor prevents deleted occurrences from being recreated.
      await txn.update(
        DatabaseHelper.tableRecorrencias,
        {'proximoMes': limit + 1},
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    }
    return count;
  }

  Future<RecurringExpense?> getRecorrencia(String id) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      DatabaseHelper.tableRecorrencias,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : RecurringExpense.fromMap(rows.single);
  }

  Future<void> atualizarRecorrencia(String id, Gasto edited) async {
    if (edited.vencimento == null) throw ArgumentError('Missing due date');
    final from = monthIndex(edited.ano, edited.mes);
    final due = edited.vencimento!;
    final offset = monthIndex(due.year, due.month) - from;
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseHelper.tableRecorrencias,
        {
          'origem': edited.origem,
          'valor': edited.valor,
          'categoria': edited.categoria,
          'diaVencimento': due.day,
          'deslocamentoVencimento': offset,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final rows = await txn.query(
        DatabaseHelper.tableGastos,
        where: 'recorrenciaId = ? AND pago = 0 AND (ano * 12 + mes - 1) >= ?',
        whereArgs: [id, from],
      );
      for (final row in rows) {
        final expense = Gasto.fromMap(row);
        final month = monthAt(monthIndex(expense.ano, expense.mes) + offset);
        final last = DateTime(month.year, month.month + 1, 0).day;
        await txn.update(
          DatabaseHelper.tableGastos,
          {
            'origem': edited.origem,
            'valor': edited.valor,
            'categoria': edited.categoria,
            'vencimento': DateTime(
              month.year,
              month.month,
              due.day.clamp(1, last),
            ).toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [expense.id],
        );
      }
    });
    await NotificationService().refreshAfterChange();
  }

  Future<void> encerrarRecorrencia(String id, int mes, int ano) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseHelper.tableRecorrencias,
        {'ativo': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        DatabaseHelper.tableGastos,
        where: 'recorrenciaId = ? AND pago = 0 AND (ano * 12 + mes - 1) > ?',
        whereArgs: [id, monthIndex(ano, mes)],
      );
    });
    await NotificationService().refreshAfterChange();
  }

  Future<Map<DateTime, double>> getCompromissosFuturos(int mes, int ano) async {
    final start = monthIndex(ano, mes) + 1;
    final db = await _databaseHelper.database;
    final rows = await db.rawQuery(
      '''SELECT ano, mes, SUM(valor) AS total FROM gastos
      WHERE pago = 0 AND (parcelaGrupo IS NOT NULL OR recorrenciaId IS NOT NULL)
      AND (ano * 12 + mes - 1) BETWEEN ? AND ? GROUP BY ano, mes''',
      [start, start + 2],
    );
    final totals = {for (var i = 0; i < 3; i++) monthAt(start + i): 0.0};
    for (final row in rows) {
      totals[DateTime(row['ano'] as int, row['mes'] as int)] =
          (row['total'] as num).toDouble();
    }
    return totals;
  }
}
