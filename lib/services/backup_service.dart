import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';
import '../models/gasto.dart';
import '../models/backup_document.dart';
import '../models/recurring_expense.dart';
import 'notification_service.dart';

/// Backup de todos os meses, incluindo contas pagas e vencimentos.
class BackupService {
  BackupService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directoryProvider;
  Future<List<File>> listarBackupsLocais() async {
    final directory = await _directoryProvider();
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              entry.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('finantech_backup_') &&
              entry.path.endsWith('.json'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
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
    final directory = await _directoryProvider();
    final file = File(
      '${directory.path}/finantech_backup_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await file.writeAsString(
      encode(rows.map(Gasto.fromMap).toList(), recorrencias: rules),
      flush: true,
    );
    return file.path;
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
    await NotificationService().refreshAfterChange();
  }
}
