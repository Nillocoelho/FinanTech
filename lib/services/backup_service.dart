import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/database_helper.dart';
import '../models/gasto.dart';
import 'notification_service.dart';

/// Backup de todos os meses, incluindo contas pagas e vencimentos.
class BackupService {
  Future<List<File>> listarBackupsLocais() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = await directory.list().where((entry) => entry is File &&
        entry.path.split(Platform.pathSeparator).last.startsWith('finantech_backup_') &&
        entry.path.endsWith('.json')).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static String encode(List<Gasto> gastos) => jsonEncode({
        'app': 'FinanTech',
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'gastos': gastos.map((gasto) => gasto.toMap()).toList(),
      });

  static List<Gasto> decode(String content) {
    final data = jsonDecode(content);
    if (data is! Map || data['app'] != 'FinanTech' ||
        data['version'] != 1 || data['gastos'] is! List) {
      throw const FormatException('Arquivo de backup incompatível.');
    }
    final gastos = <Gasto>[];
    final ids = <int>{};
    for (final row in data['gastos'] as List) {
      if (row is! Map<String, dynamic> ||
          row['id'] is! int || (row['id'] as int) <= 0 ||
          row['origem'] is! String || (row['origem'] as String).trim().isEmpty ||
          row['valor'] is! num || !(row['valor'] as num).isFinite ||
          (row['valor'] as num) <= 0 ||
          row['mes'] is! int || (row['mes'] as int) < 1 || (row['mes'] as int) > 12 ||
          row['ano'] is! int || (row['ano'] as int) < 2000 || (row['ano'] as int) > 2100 ||
          row['pago'] is! int || (row['pago'] != 0 && row['pago'] != 1) ||
          row['createdAt'] is! String ||
          DateTime.tryParse(row['createdAt'] as String) == null ||
          (row['vencimento'] != null &&
              (row['vencimento'] is! String ||
                  DateTime.tryParse(row['vencimento'] as String) == null))) {
        throw const FormatException('O backup contém um gasto inválido.');
      }
      final gasto = Gasto.fromMap(row);
      if (!ids.add(gasto.id!)) {
        throw const FormatException('O backup contém identificadores repetidos.');
      }
      gastos.add(gasto);
    }
    return gastos;
  }

  Future<String> criarBackup() async {
    final db = await DatabaseHelper().database;
    final rows = await db.query(DatabaseHelper.tableGastos, orderBy: 'id');
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/finantech_backup_${DateTime.now().microsecondsSinceEpoch}.json');
    await file.writeAsString(encode(rows.map(Gasto.fromMap).toList()), flush: true);
    return file.path;
  }

  /// A transação impede restaurações parciais em caso de falha.
  Future<void> restaurar(List<Gasto> gastos) async {
    // Uma cópia local dos dados atuais permite desfazer a substituição.
    await criarBackup();
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      await txn.delete(DatabaseHelper.tableGastos);
      final batch = txn.batch();
      for (final gasto in gastos) {
        batch.insert(DatabaseHelper.tableGastos, gasto.toMap());
      }
      await batch.commit(noResult: true);
    });
    await NotificationService().refreshAfterChange();
  }
}
