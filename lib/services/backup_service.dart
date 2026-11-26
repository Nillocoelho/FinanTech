import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';
import '../data/gastos_repository.dart';
import '../models/gasto.dart';
import '../models/backup_document.dart';
import '../models/recurring_expense.dart';

/// Backup de todos os meses, incluindo contas pagas e vencimentos.
class BackupService {
  BackupService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directoryProvider;

  /// Quantidade de backups locais mantidos; os mais antigos são apagados.
  static const int maxBackupsLocais = 10;

  /// Prefixo dos novos arquivos; o antigo continua aceito na restauração.
  static const String prefixo = 'diazen_backup_';
  static const List<String> _prefixos = [
    prefixo,
    'quitora_backup_',
    'quita_backup_',
    'finantech_backup_',
  ];

  static int _carimbo(File file) {
    final nome = file.path.split(Platform.pathSeparator).last;
    final digitos = RegExp(r'(\d+)\.json$').firstMatch(nome)?.group(1);
    return int.tryParse(digitos ?? '') ?? 0;
  }

  /// Backups locais, do mais recente para o mais antigo.
  Future<List<File>> listarBackupsLocais() async {
    final directory = await _directoryProvider();
    final files = await directory
        .list()
        .where((entry) {
          if (entry is! File || !entry.path.endsWith('.json')) return false;
          final nome = entry.path.split(Platform.pathSeparator).last;
          return _prefixos.any(nome.startsWith);
        })
        .cast<File>()
        .toList();
    files.sort((a, b) => _carimbo(b).compareTo(_carimbo(a)));
    return files;
  }

  static String encode(
    List<Gasto> gastos, {
    List<RecurringExpense> recorrencias = const [],
  }) => BackupDocument(gastos, recorrencias).encode();
  static List<Gasto> decode(String content) =>
      BackupDocument.decode(content).gastos;
  static BackupDocument decodeDocument(String content) =>
      BackupDocument.decode(content);

  Future<String> criarBackup() async {
    final db = await DatabaseHelper().database;
    final snapshot = await db.transaction(
      (txn) async => (
        gastos: await txn.query(DatabaseHelper.tableGastos, orderBy: 'id'),
        regras: await txn.query(DatabaseHelper.tableRecorrencias),
      ),
    );
    final rows = snapshot.gastos;
    final rules = snapshot.regras.map(RecurringExpense.fromMap).toList();
    final content = encode(rows.map(Gasto.fromMap).toList(), recorrencias: rules);
    // Falha agora, e não na restauração, se algum dado não puder ser lido de
    // volta (por exemplo um ano fora de 2000–2100).
    BackupDocument.decode(content);
    final directory = await _directoryProvider();
    final file = File(
      '${directory.path}/$prefixo${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await file.writeAsString(content, flush: true);
    await _rotacionar();
    return file.path;
  }

  Future<void> _rotacionar() async {
    final files = await listarBackupsLocais();
    for (final antigo in files.skip(maxBackupsLocais)) {
      try {
        await antigo.delete();
      } on FileSystemException {
        // Um arquivo preso não impede o backup recém-criado.
      }
    }
  }

  /// A transação impede restaurações parciais em caso de falha.
  Future<void> restaurar(
    List<Gasto> gastos, {
    List<RecurringExpense> recorrencias = const [],
  }) async {
    BackupDocument.decode(encode(gastos, recorrencias: recorrencias));
    // Uma cópia local dos dados atuais permite desfazer a substituição.
    await criarBackup();
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      await txn.delete(DatabaseHelper.tableGastos);
      await txn.delete(DatabaseHelper.tableRecorrencias);
      final batch = txn.batch();
      for (final rule in recorrencias) {
        batch.insert(DatabaseHelper.tableRecorrencias, rule.toMap());
      }
      for (final gasto in gastos) {
        batch.insert(DatabaseHelper.tableGastos, gasto.toMap());
      }
      await batch.commit(noResult: true);
    });
    GastosRepository.notificarAlteracao();
  }
}
