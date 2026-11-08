import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Classe responsável por gerenciar a conexão com o banco de dados SQLite.
///
/// Utiliza o padrão Singleton para garantir apenas uma instância do banco
/// durante toda a execução do aplicativo.
class DatabaseHelper {
  // Nome do arquivo do banco de dados
  static const String _databaseName = 'finantech.db';

  // Versão do banco (incrementar quando houver mudanças na estrutura)
  static const int _databaseVersion = 3;

  // Nome da tabela de gastos
  static const String tableGastos = 'gastos';
  static const String tableRecorrencias = 'recorrencias';

  // Instância única do DatabaseHelper (Singleton)
  static DatabaseHelper? _instance;

  // Instância do banco de dados
  static Database? _database;

  // Construtor privado para implementar Singleton
  DatabaseHelper._internal();

  /// Factory constructor que retorna sempre a mesma instância
  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  /// Getter que retorna o banco de dados, inicializando-o se necessário
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Inicializa o banco de dados
  ///
  /// Obtém o caminho do diretório de banco de dados do dispositivo,
  /// concatena com o nome do arquivo e abre/cria o banco.
  Future<Database> _initDatabase() async {
    // Obtém o caminho padrão para bancos de dados no dispositivo
    final String databasesPath = await getDatabasesPath();
    final String path = join(databasesPath, _databaseName);

    // Abre o banco de dados (ou cria se não existir)
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Callback executado quando o banco é criado pela primeira vez
  ///
  /// Cria a tabela 'gastos' com todas as colunas necessárias.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableGastos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        origem TEXT NOT NULL,
        valor REAL NOT NULL,
        pago INTEGER NOT NULL DEFAULT 0,
        mes INTEGER NOT NULL,
        ano INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        vencimento TEXT,
        categoria TEXT NOT NULL DEFAULT 'Sem categoria',
        parcelaGrupo TEXT,
        parcelaNumero INTEGER,
        parcelaTotal INTEGER,
        recorrenciaId TEXT
      )
    ''');

    // Cria um índice para otimizar consultas por mês/ano
    await db.execute('''
      CREATE INDEX idx_gastos_mes_ano ON $tableGastos (mes, ano)
    ''');

    // Cria um índice para otimizar consultas por origem
    await db.execute('''
      CREATE INDEX idx_gastos_origem ON $tableGastos (origem)
    ''');
    await _createPlanningTables(db);
  }

  /// Callback executado quando a versão do banco é atualizada
  ///
  /// Permite migrar dados ou estrutura quando o app é atualizado.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE gastos ADD COLUMN vencimento TEXT');
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE gastos ADD COLUMN categoria TEXT NOT NULL DEFAULT 'Sem categoria'",
      );
      for (final column in [
        'parcelaGrupo TEXT',
        'parcelaNumero INTEGER',
        'parcelaTotal INTEGER',
        'recorrenciaId TEXT',
      ]) {
        await db.execute('ALTER TABLE gastos ADD COLUMN $column');
      }
      await _createPlanningTables(db);
    }
    // Implementar migrações futuras aqui se necessário
    // Exemplo:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE gastos ADD COLUMN nova_coluna TEXT');
    // }
  }

  Future<void> _createPlanningTables(Database db) async {
    await db.execute('''CREATE TABLE recorrencias (
      id TEXT PRIMARY KEY, origem TEXT NOT NULL, valor REAL NOT NULL,
      categoria TEXT NOT NULL, inicioMes INTEGER NOT NULL,
      proximoMes INTEGER NOT NULL, diaVencimento INTEGER NOT NULL,
      deslocamentoVencimento INTEGER NOT NULL, ativo INTEGER NOT NULL DEFAULT 1
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_recorrencia_periodo ON gastos (recorrenciaId, ano, mes)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_parcela_numero ON gastos (parcelaGrupo, parcelaNumero)',
    );
  }

  /// Fecha a conexão com o banco de dados
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
