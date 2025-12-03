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
    
    return await db.insert(
      DatabaseHelper.tableGastos,
      gasto.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retorna todos os gastos de um mês/ano específico
  /// 
  /// Os gastos são ordenados pela data de criação (mais recentes primeiro).
  Future<List<Gasto>> getGastosDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      DatabaseHelper.tableGastos,
      where: 'mes = ? AND ano = ?',
      whereArgs: [mes, ano],
      orderBy: 'createdAt DESC',
    );

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
    
    return await db.update(
      DatabaseHelper.tableGastos,
      {'pago': pago ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Calcula o total de gastos não pagos de um mês/ano
  /// 
  /// Soma todos os valores onde 'pago = 0' para o mês/ano especificado.
  /// Retorna 0.0 se não houver gastos ou se todos estiverem pagos.
  Future<double> getTotalDoMes(int mes, int ano) async {
    final db = await _databaseHelper.database;
    
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(valor), 0.0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
    ''', [mes, ano]);

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
    
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT origem, COALESCE(SUM(valor), 0.0) as total
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ? AND pago = 0
      GROUP BY origem
      ORDER BY total DESC
    ''', [mes, ano]);

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
    
    return await db.delete(
      DatabaseHelper.tableGastos,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Atualiza um gasto existente
  /// 
  /// [gasto] deve conter o id do gasto a ser atualizado.
  /// Retorna o número de linhas afetadas.
  Future<int> updateGasto(Gasto gasto) async {
    final db = await _databaseHelper.database;
    
    return await db.update(
      DatabaseHelper.tableGastos,
      gasto.toMap(),
      where: 'id = ?',
      whereArgs: [gasto.id],
    );
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
  Future<bool> existeGastoComOrigem(String origem, int mes, int ano, {int? excludeId}) async {
    final db = await _databaseHelper.database;
    
    String query = '''
      SELECT COUNT(*) as count
      FROM ${DatabaseHelper.tableGastos}
      WHERE LOWER(origem) = LOWER(?) AND mes = ? AND ano = ?
    ''';
    List<dynamic> args = [origem.trim(), mes, ano];
    
    if (excludeId != null) {
      query += ' AND id != ?';
      args.add(excludeId);
    }
    
    final result = await db.rawQuery(query, args);
    final count = (result.first['count'] as num).toInt();
    return count > 0;
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
    
    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN pago = 0 THEN valor ELSE 0 END), 0.0) as totalEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN valor ELSE 0 END), 0.0) as totalPago,
        COALESCE(SUM(CASE WHEN pago = 0 THEN 1 ELSE 0 END), 0) as quantidadeEmAberto,
        COALESCE(SUM(CASE WHEN pago = 1 THEN 1 ELSE 0 END), 0) as quantidadePaga
      FROM ${DatabaseHelper.tableGastos}
      WHERE mes = ? AND ano = ?
    ''', [mes, ano]);

    final row = result.first;
    return {
      'totalEmAberto': (row['totalEmAberto'] as num).toDouble(),
      'totalPago': (row['totalPago'] as num).toDouble(),
      'quantidadeEmAberto': (row['quantidadeEmAberto'] as num).toInt(),
      'quantidadePaga': (row['quantidadePaga'] as num).toInt(),
    };
  }
}
