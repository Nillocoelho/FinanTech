import 'gasto.dart';

int monthIndex(int year, int month) => year * 12 + month - 1;
DateTime monthAt(int index) => DateTime(index ~/ 12, index % 12 + 1);

/// The day and month offset are kept separately to preserve day 31 after February.
class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.origem,
    required this.valor,
    required this.categoria,
    required this.inicioMes,
    required this.proximoMes,
    required this.diaVencimento,
    required this.deslocamentoVencimento,
    this.ativo = true,
  });
  final String id, origem, categoria;
  final double valor;
  final int inicioMes, proximoMes, diaVencimento, deslocamentoVencimento;
  final bool ativo;

  Gasto occurrence(int index, DateTime now) {
    final period = monthAt(index);
    final due = monthAt(index + deslocamentoVencimento);
    final last = DateTime(due.year, due.month + 1, 0).day;
    return Gasto(
      origem: origem,
      valor: valor,
      categoria: categoria,
      pago: false,
      mes: period.month,
      ano: period.year,
      createdAt: now.toIso8601String(),
      vencimento: DateTime(due.year, due.month, diaVencimento.clamp(1, last)),
      recorrenciaId: id,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'origem': origem,
    'valor': valor,
    'categoria': categoria,
    'inicioMes': inicioMes,
    'proximoMes': proximoMes,
    'diaVencimento': diaVencimento,
    'deslocamentoVencimento': deslocamentoVencimento,
    'ativo': ativo ? 1 : 0,
  };
  factory RecurringExpense.fromMap(Map<String, dynamic> row) =>
      RecurringExpense(
        id: row['id'] as String,
        origem: row['origem'] as String,
        valor: (row['valor'] as num).toDouble(),
        categoria: row['categoria'] as String,
        inicioMes: row['inicioMes'] as int,
        proximoMes: row['proximoMes'] as int,
        diaVencimento: row['diaVencimento'] as int,
        deslocamentoVencimento: row['deslocamentoVencimento'] as int,
        ativo: row['ativo'] == 1,
      );
}
