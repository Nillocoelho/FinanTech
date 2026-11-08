import 'dart:convert';

import 'gasto.dart';
import 'recurring_expense.dart';

class BackupDocument {
  const BackupDocument(this.gastos, this.recorrencias);
  final List<Gasto> gastos;
  final List<RecurringExpense> recorrencias;

  static bool _text(Object? value) =>
      value is String && value.trim().isNotEmpty;
  static bool _integer(Object? value, int min, int max) =>
      value is int && value >= min && value <= max;
  static bool _amount(Object? value) =>
      value is num && value.isFinite && value > 0;
  static Never _invalid() => throw const FormatException(
    'O backup contém dados inválidos ou incompletos.',
  );

  factory BackupDocument.decode(String content) {
    final data = jsonDecode(content);
    if (data is! Map ||
        data['app'] != 'FinanTech' ||
        (data['version'] != 1 && data['version'] != 2) ||
        data['gastos'] is! List ||
        (data['version'] == 2 && data['recorrencias'] is! List)) {
      throw const FormatException('Arquivo de backup incompatível.');
    }
    final rules = <RecurringExpense>[];
    final ruleIds = <String>{};
    for (final row in (data['recorrencias'] as List? ?? [])) {
      if (row is! Map<String, dynamic> ||
          !_text(row['id']) ||
          !_text(row['origem']) ||
          !_text(row['categoria']) ||
          !_amount(row['valor']) ||
          !_integer(
            row['inicioMes'],
            monthIndex(2000, 1),
            monthIndex(2100, 12),
          ) ||
          !_integer(
            row['proximoMes'],
            row['inicioMes'] as int,
            monthIndex(2100, 12) + 1,
          ) ||
          !_integer(row['diaVencimento'], 1, 31) ||
          !_integer(row['deslocamentoVencimento'], -1211, 1211) ||
          !_integer(row['ativo'], 0, 1) ||
          !ruleIds.add(row['id'] as String)) {
        _invalid();
      }
      rules.add(RecurringExpense.fromMap(row));
    }
    final expenses = <Gasto>[];
    final ids = <int>{};
    final installmentKeys = <String>{};
    final recurringKeys = <String>{};
    final groupTotals = <String, int>{};
    for (final row in data['gastos'] as List) {
      if (row is! Map<String, dynamic> ||
          !_integer(row['id'], 1, 0x7fffffff) ||
          !_text(row['origem']) ||
          !_amount(row['valor']) ||
          !_integer(row['mes'], 1, 12) ||
          !_integer(row['ano'], 2000, 2100) ||
          !_integer(row['pago'], 0, 1) ||
          row['createdAt'] is! String ||
          DateTime.tryParse(row['createdAt'] as String) == null ||
          (row['vencimento'] != null &&
              (row['vencimento'] is! String ||
                  DateTime.tryParse(row['vencimento'] as String) == null)) ||
          (row['categoria'] != null && !_text(row['categoria'])) ||
          (row['recorrenciaId'] != null &&
              (!_text(row['recorrenciaId']) ||
                  !ruleIds.contains(row['recorrenciaId']))) ||
          !ids.add(row['id'] as int)) {
        _invalid();
      }
      final group = row['parcelaGrupo'];
      if (group == null) {
        if (row['parcelaNumero'] != null || row['parcelaTotal'] != null) {
          _invalid();
        }
      } else {
        if (!_text(group) ||
            row['recorrenciaId'] != null ||
            !_integer(row['parcelaTotal'], 2, 120) ||
            !_integer(row['parcelaNumero'], 1, row['parcelaTotal'] as int) ||
            !installmentKeys.add('$group:${row['parcelaNumero']}')) {
          _invalid();
        }
        final total = row['parcelaTotal'] as int;
        if (groupTotals.containsKey(group) && groupTotals[group] != total) {
          _invalid();
        }
        groupTotals[group as String] = total;
      }
      if (row['recorrenciaId'] != null &&
          !recurringKeys.add(
            '${row['recorrenciaId']}:${row['ano']}:${row['mes']}',
          )) {
        _invalid();
      }
      expenses.add(Gasto.fromMap(row));
    }
    return BackupDocument(expenses, rules);
  }

  String encode() => jsonEncode({
    'app': 'FinanTech',
    'version': 2,
    'createdAt': DateTime.now().toIso8601String(),
    'gastos': gastos.map((g) => g.toMap()).toList(),
    'recorrencias': recorrencias.map((r) => r.toMap()).toList(),
  });
}
