import 'dart:async';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/gasto.dart';
import '../models/recurring_expense.dart';
import '../utils/installment_helper.dart';
import 'database_helper.dart';

/// Repositório responsável por todas as operações de CRUD na tabela de gastos.
///
/// Esta classe abstrai a lógica de acesso ao banco de dados, fornecendo
/// métodos de alto nível para manipular os gastos.
///
/// O repositório não conhece os lembretes: cada gravação emite um evento em
/// [changes], e a camada do app decide quando ressincronizar (com debounce).
class GastosRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  /// Meses gravados à frente do mês atual (o atual + 11). Além disso, as
  /// recorrências são apenas projetadas em memória.
  static const int mesesMaterializados = 12;

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  /// Emite um evento depois de cada gravação concluída.
  static Stream<void> get changes => _changes.stream;

  /// Avisa os ouvintes de [changes]; use após gravações feitas fora do
  /// repositório (restauração de backup, importação).
  static void notificarAlteracao() => _changes.add(null);

  // Ocorrências projetadas recebem ids negativos estáveis durante a execução,
  // para que a interface possa pagar, editar ou excluir como qualquer gasto.
  static final Map<int, ({String regra, int mes})> _projecoes = {};
  static final Map<String, int> _idsProjecao = {};

  static int _idProjecao(String regra, int mes) =>
      _idsProjecao.putIfAbsent('$regra:$mes', () {
        final id = -(_idsProjecao.length + 1);
        _projecoes[id] = (regra: regra, mes: mes);
        return id;
      });

  /// Insere um novo gasto no banco de dados
  ///
  /// Recebe um objeto [Gasto] e o persiste no SQLite.
  /// O campo 'id' será gerado automaticamente pelo banco.
  /// Um conflito com os índices únicos de parcela/recorrência gera erro em vez
  /// de substituir silenciosamente uma linha existente.
  Future<int> insertGasto(Gasto gasto) async {
    final db = await _databaseHelper.database;

    final result = await db.insert(
      DatabaseHelper.tableGastos,
      gasto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    notificarAlteracao();
    return result;
  }

  /// Retorna todos os gastos de um mês/ano específico
  ///
  /// Os gastos são ordenados pela data de criação (mais recentes primeiro).
  /// Meses além da janela gravada incluem as recorrências ativas projetadas
  /// (com id negativo, ver [Gasto.projetado]).
  Future<List<Gasto>> getGastosDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;

    final maps = await db.rawQuery(
      '''SELECT gastos.*, recorrencias.ativo AS recorrenciaAtiva
      FROM gastos LEFT JOIN recorrencias ON gastos.recorrenciaId = recorrencias.id
      WHERE gastos.mes = ? AND gastos.ano = ? ORDER BY gastos.createdAt DESC''',
      [mes, ano],
    );

    final gastos = maps.map(Gasto.fromMap).toList();
    final index = monthIndex(ano, mes);
    final clock = DateTime.now();
    for (final rule in await _regrasProjetaveis(db, index)) {
      gastos.add(
        rule.occurrence(index, clock, id: _idProjecao(rule.id, index)),
      );
    }
    return gastos;
  }

  /// Regras ativas cuja ocorrência do mês [index] ainda não foi gravada.
  Future<List<RecurringExpense>> _regrasProjetaveis(
    DatabaseExecutor db,
    int index,
  ) async {
    if (index > monthIndex(2100, 12)) return const [];
    return (await db.query(
      DatabaseHelper.tableRecorrencias,
      where: 'ativo = 1 AND proximoMes <= ? AND inicioMes <= ?',
      whereArgs: [index, index],
    )).map(RecurringExpense.fromMap).toList();
  }

  /// Grava a ocorrência projetada [id] (e os meses anteriores da regra, para
  /// manter o cursor consistente) e devolve o id real.
  Future<int> _idReal(int id) async {
    if (id >= 0) return id;
    final projecao = _projecoes[id];
    if (projecao == null) {
      throw StateError('Ocorrência projetada desconhecida: $id');
    }
    final db = await _databaseHelper.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseHelper.tableRecorrencias,
        where: 'id = ?',
        whereArgs: [projecao.regra],
      );
      if (rows.isEmpty) throw StateError('Recorrência não encontrada.');
      final rule = RecurringExpense.fromMap(rows.single);
      await _materializarRegras(txn, [rule], projecao.mes, DateTime.now());
      final period = monthAt(projecao.mes);
      final gravado = await txn.query(
        DatabaseHelper.tableGastos,
        columns: ['id'],
        where: 'recorrenciaId = ? AND ano = ? AND mes = ?',
        whereArgs: [rule.id, period.year, period.month],
      );
      if (gravado.isEmpty) throw StateError('Ocorrência não encontrada.');
      return gravado.single['id'] as int;
    });
  }

  /// Atualiza o status de pagamento de um gasto
  ///
  /// [id] é o identificador do gasto a ser atualizado.
  /// [pago] indica se o gasto foi pago (true) ou não (false).
  Future<int> atualizarPago(int id, bool pago) async {
    final realId = await _idReal(id);
    final db = await _databaseHelper.database;

    final result = await db.update(
      DatabaseHelper.tableGastos,
      {'pago': pago ? 1 : 0},
      where: 'id = ?',
      whereArgs: [realId],
    );
    notificarAlteracao();
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
      SELECT COALESCE(SUM(valorCentavos), 0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
    ''',
      [mes, ano],
    );

    return (result.first['total'] as num).toInt() / 100;
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
      SELECT origem, COALESCE(SUM(valorCentavos), 0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
      GROUP BY origem
      ORDER BY total DESC
    ''',
      [mes, ano],
    );

    return {
      for (final row in result)
        row['origem'] as String: (row['total'] as num).toInt() / 100,
    };
  }

  /// Exclui um gasto pelo ID
  ///
  /// Retorna o número de linhas afetadas (1 se excluído com sucesso, 0 se não encontrado).
  Future<int> deleteGasto(int id) async {
    final realId = await _idReal(id);
    final db = await _databaseHelper.database;

    final result = await db.delete(
      DatabaseHelper.tableGastos,
      where: 'id = ?',
      whereArgs: [realId],
    );
    notificarAlteracao();
    return result;
  }

  /// Atualiza um gasto existente
  ///
  /// [gasto] deve conter o id do gasto a ser atualizado.
  /// Retorna o número de linhas afetadas.
  Future<int> updateGasto(Gasto gasto) async {
    final realId = await _idReal(gasto.id!);
    final db = await _databaseHelper.database;

    final result = await db.update(
      DatabaseHelper.tableGastos,
      gasto.copyWith(id: realId).toMap(),
      where: 'id = ?',
      whereArgs: [realId],
    );
    notificarAlteracao();
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

  /// Insere um novo gasto ou soma seu valor a um gasto existente da mesma
  /// origem/mês/ano/categoria **ainda em aberto**.
  ///
  /// Um lançamento já pago nunca é alterado: nesse caso um novo é inserido.
  /// Retorna `somado = true` quando um registro existente foi atualizado.
  Future<({bool somado, Gasto gasto})> salvarSomandoSeExistir(
    Gasto gasto,
  ) async {
    final db = await _databaseHelper.database;
    final matches = await db.query(
      DatabaseHelper.tableGastos,
      where:
          'LOWER(origem) = LOWER(?) AND mes = ? AND ano = ? AND categoria = ? AND pago = 0 AND parcelaGrupo IS NULL AND recorrenciaId IS NULL',
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
      valorCentavos: gastoExistente.valorCentavos + gasto.valorCentavos,
      vencimento: gasto.vencimento,
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
        COALESCE(SUM(CASE WHEN pago = 0 THEN valorCentavos ELSE 0 END), 0) as totalEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN valorCentavos ELSE 0 END), 0) as totalPago,
        COALESCE(SUM(CASE WHEN pago = 0 THEN 1 ELSE 0 END), 0) as quantidadeEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN 1 ELSE 0 END), 0) as quantidadePaga
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ?
    ''',
      [mes, ano],
    );

    final row = result.first;
    return {
      'totalEmAberto': (row['totalEmAberto'] as num).toInt() / 100,
      'totalPago': (row['totalPago'] as num).toInt() / 100,
      'quantidadeEmAberto': (row['quantidadeEmAberto'] as num).toInt(),
      'quantidadePaga': (row['quantidadePaga'] as num).toInt(),
    };
  }

  String _seriesId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${List.generate(4, (_) => Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0')).join()}';

  Future<void> criarParcelamento(Gasto base, int quantidade) async {
    if (quantidade < 2 ||
        quantidade > 120 ||
        base.valorCentavos < quantidade ||
        base.vencimento == null) {
      throw ArgumentError('Invalid installment plan');
    }
    final group = _seriesId();
    final values = InstallmentHelper.splitCentavos(
      base.valorCentavos,
      quantidade,
    );
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
            valorCentavos: values[i],
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
    notificarAlteracao();
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

  /// Último mês gravado: o mês de [clock] mais 11.
  static int _horizonte(DateTime clock) =>
      monthIndex(clock.year, clock.month) + mesesMaterializados - 1;

  Future<void> criarRecorrencia(Gasto base, {DateTime? now}) async {
    if (base.vencimento == null || base.valorCentavos <= 0) {
      throw ArgumentError('Invalid recurring expense');
    }
    final clock = now ?? DateTime.now();
    final start = monthIndex(base.ano, base.mes);
    final rule = RecurringExpense(
      id: _seriesId(),
      origem: base.origem,
      valorCentavos: base.valorCentavos,
      categoria: base.categoria,
      inicioMes: start,
      proximoMes: start,
      diaVencimento: base.vencimento!.day,
      deslocamentoVencimento:
          monthIndex(base.vencimento!.year, base.vencimento!.month) - start,
    );
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseHelper.tableRecorrencias,
        rule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _materialize(txn, _horizonte(clock), clock);
    });
    notificarAlteracao();
  }

  /// Grava as recorrências até hoje + 11 meses.
  ///
  /// Meses posteriores, como um mês distante aberto pelo usuário, não são
  /// gravados: [getGastosDoMes] os projeta em memória.
  Future<void> prepararMes(int mes, int ano, {DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final db = await _databaseHelper.database;
    final count = await db.transaction(
      (txn) => _materialize(txn, _horizonte(clock), clock),
    );
    if (count > 0) notificarAlteracao();
  }

  Future<int> _materialize(Transaction txn, int through, DateTime now) async {
    final limit = min(through, monthIndex(2100, 12));
    final rules = (await txn.query(
      DatabaseHelper.tableRecorrencias,
      where: 'ativo = 1 AND proximoMes <= ?',
      whereArgs: [limit],
    )).map(RecurringExpense.fromMap).toList();
    return _materializarRegras(txn, rules, limit, now);
  }

  Future<int> _materializarRegras(
    Transaction txn,
    List<RecurringExpense> rules,
    int through,
    DateTime now,
  ) async {
    final limit = min(through, monthIndex(2100, 12));
    final batch = txn.batch();
    var count = 0;
    for (final rule in rules) {
      if (rule.proximoMes > limit) continue;
      for (var index = rule.proximoMes; index <= limit; index++) {
        batch.insert(
          DatabaseHelper.tableGastos,
          rule.occurrence(index, now).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count++;
      }
      // A cursor prevents deleted occurrences from being recreated.
      batch.update(
        DatabaseHelper.tableRecorrencias,
        {'proximoMes': limit + 1},
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    }
    await batch.commit(noResult: true);
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
          'valorCentavos': edited.valorCentavos,
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
      final batch = txn.batch();
      for (final row in rows) {
        final expense = Gasto.fromMap(row);
        final month = monthAt(monthIndex(expense.ano, expense.mes) + offset);
        final last = DateTime(month.year, month.month + 1, 0).day;
        batch.update(
          DatabaseHelper.tableGastos,
          {
            'origem': edited.origem,
            'valor': edited.valor,
            'valorCentavos': edited.valorCentavos,
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
      await batch.commit(noResult: true);
    });
    notificarAlteracao();
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
    notificarAlteracao();
  }

  Future<Map<DateTime, double>> getCompromissosFuturos(int mes, int ano) async {
    final start = monthIndex(ano, mes) + 1;
    final db = await _databaseHelper.database;
    final rows = await db.rawQuery(
      '''SELECT ano, mes, SUM(valorCentavos) AS total FROM gastos
      WHERE pago = 0 AND (parcelaGrupo IS NOT NULL OR recorrenciaId IS NOT NULL)
      AND (ano * 12 + mes - 1) BETWEEN ? AND ? GROUP BY ano, mes''',
      [start, start + 2],
    );
    final cents = {for (var i = 0; i < 3; i++) monthAt(start + i): 0};
    for (final row in rows) {
      cents[DateTime(row['ano'] as int, row['mes'] as int)] =
          (row['total'] as num).toInt();
    }
    // Meses ainda não gravados recebem as recorrências projetadas.
    for (var i = 0; i < 3; i++) {
      for (final rule in await _regrasProjetaveis(db, start + i)) {
        cents.update(monthAt(start + i), (v) => v + rule.valorCentavos);
      }
    }
    return cents.map((month, value) => MapEntry(month, value / 100));
  }
}
