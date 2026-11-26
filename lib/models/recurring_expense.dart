import 'gasto.dart';

int monthIndex(int year, int month) => year * 12 + month - 1;
DateTime monthAt(int index) => DateTime(index ~/ 12, index % 12 + 1);

/// The day and month offset are kept separately to preserve day 31 after February.
class RecurringExpense {
  /// Informe [valor] (reais) ou [valorCentavos]; os centavos têm prioridade.
  RecurringExpense({
    required this.id,
    required this.origem,
    double? valor,
    int? valorCentavos,
    required this.categoria,
    required this.inicioMes,
    required this.proximoMes,
    required this.diaVencimento,
    required this.deslocamentoVencimento,
    this.ativo = true,
  }) : assert(valor != null || valorCentavos != null),
       valorCentavos = valorCentavos ?? Gasto.paraCentavos(valor!);
  final String id, origem, categoria;
  final int valorCentavos;
  double get valor => valorCentavos / 100;
  final int inicioMes, proximoMes, diaVencimento, deslocamentoVencimento;
  final bool ativo;

  /// Ocorrência do mês [index]; [id] permite marcar projeções em memória.
  Gasto occurrence(int index, DateTime now, {int? id}) {
    final period = monthAt(index);
    final due = monthAt(index + deslocamentoVencimento);
    final last = DateTime(due.year, due.month + 1, 0).day;
    return Gasto(
      id: id,
      origem: origem,
      valorCentavos: valorCentavos,
      categoria: categoria,
      pago: false,
      mes: period.month,
      ano: period.year,
      createdAt: now.toIso8601String(),
      vencimento: DateTime(due.year, due.month, diaVencimento.clamp(1, last)),
      recorrenciaId: this.id,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'origem': origem,
    'valor': valor,
    'valorCentavos': valorCentavos,
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
        valorCentavos: Gasto.centavosDoMapa(row),
        categoria: row['categoria'] as String,
        inicioMes: row['inicioMes'] as int,
        proximoMes: row['proximoMes'] as int,
        diaVencimento: row['diaVencimento'] as int,
        deslocamentoVencimento: row['deslocamentoVencimento'] as int,
        ativo: row['ativo'] == 1,
      );
}
