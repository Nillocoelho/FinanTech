import 'package:finantech/data/gastos_repository.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/models/recurring_expense.dart';
import 'package:finantech/utils/installment_helper.dart';

final fixtureNow = DateTime(2026, 11, 7, 10);

class PreviewRepository extends GastosRepository {
  PreviewRepository({bool empty = false, this.fail = false}) {
    if (!empty) {
      final rows = <(String, double, bool, int)>[
        ('Aluguel', 1450, false, 5),
        ('Nubank', 980, false, 12),
        ('Energia', 186.90, false, 10),
        ('Internet', 119.90, false, 15),
        ('Mercado', 640.25, true, 3),
      ];
      for (final row in rows) {
        expenses.add(
          Gasto(
            id: expenses.length + 1,
            origem: row.$1,
            valor: row.$2,
            pago: row.$3,
            mes: 11,
            ano: 2026,
            createdAt: '2026-11-01',
            vencimento: DateTime(2026, 11, row.$4),
          ),
        );
      }
    }
  }
  final bool fail;
  final List<Gasto> expenses = [];
  final List<RecurringExpense> rules = [];
  @override
  Future<void> prepararMes(int mes, int ano, {DateTime? now}) async {}
  @override
  Future<Map<DateTime, double>> getCompromissosFuturos(int mes, int ano) async {
    final start = monthIndex(ano, mes) + 1;
    return {
      for (var i = 0; i < 3; i++)
        monthAt(start + i): expenses
            .where(
              (g) =>
                  !g.pago &&
                  (g.parcelado || g.recorrenciaId != null) &&
                  monthIndex(g.ano, g.mes) == start + i,
            )
            .fold<double>(0, (sum, g) => sum + g.valor),
    };
  }

  @override
  Future<List<Gasto>> getParcelas(String grupo) async =>
      expenses.where((g) => g.parcelaGrupo == grupo).toList();
  @override
  Future<void> criarParcelamento(Gasto base, int quantidade) async {
    final group = 'plan-${expenses.length}';
    final parts = InstallmentHelper.splitAmount(base.valor, quantidade);
    for (var i = 0; i < quantidade; i++) {
      final period = InstallmentHelper.addMonths(base.mes, base.ano, i);
      final date = base.vencimento!;
      final last = DateTime(date.year, date.month + i + 1, 0).day;
      expenses.add(
        base.copyWith(
          id: expenses.length + 1,
          mes: period.mes,
          ano: period.ano,
          valor: parts[i],
          parcelaGrupo: group,
          parcelaNumero: i + 1,
          parcelaTotal: quantidade,
          vencimento: DateTime(
            date.year,
            date.month + i,
            date.day.clamp(1, last),
          ),
        ),
      );
    }
  }

  @override
  Future<void> criarRecorrencia(Gasto base, {DateTime? now}) async {
    final start = monthIndex(base.ano, base.mes);
    final rule = RecurringExpense(
      id: 'rule-${rules.length}',
      origem: base.origem,
      valor: base.valor,
      categoria: base.categoria,
      inicioMes: start,
      proximoMes: start + 12,
      diaVencimento: base.vencimento!.day,
      deslocamentoVencimento: 0,
    );
    rules.add(rule);
    for (var i = 0; i < 12; i++) {
      expenses.add(
        rule
            .occurrence(start + i, now ?? fixtureNow)
            .copyWith(id: expenses.length + 1),
      );
    }
  }

  @override
  Future<List<Gasto>> getGastosDoMes(int mes, int ano) async {
    if (fail) throw StateError('offline fixture failure');
    return expenses.where((g) => g.mes == mes && g.ano == ano).toList();
  }

  @override
  Future<List<String>> getOrigensDistintas() async =>
      expenses.map((g) => g.origem).toSet().toList();
  @override
  Future<int> atualizarPago(int id, bool pago) async {
    final index = expenses.indexWhere((g) => g.id == id);
    expenses[index] = expenses[index].copyWith(pago: pago);
    return 1;
  }

  @override
  Future<int> deleteGasto(int id) async {
    expenses.removeWhere((g) => g.id == id);
    return 1;
  }

  @override
  Future<bool> existeGastoComOrigem(
    String origem,
    int mes,
    int ano, {
    int? excludeId,
  }) async => expenses.any(
    (g) =>
        g.id != excludeId &&
        g.origem.toLowerCase() == origem.toLowerCase() &&
        g.mes == mes &&
        g.ano == ano,
  );
  @override
  Future<int> updateGasto(Gasto gasto) async {
    expenses[expenses.indexWhere((g) => g.id == gasto.id)] = gasto;
    return 1;
  }

  @override
  Future<({bool somado, Gasto gasto})> salvarSomandoSeExistir(
    Gasto gasto,
  ) async {
    final index = expenses.indexWhere(
      (g) =>
          g.origem.toLowerCase() == gasto.origem.toLowerCase() &&
          g.mes == gasto.mes &&
          g.ano == gasto.ano,
    );
    if (index >= 0) {
      final updated = expenses[index].copyWith(
        valor: expenses[index].valor + gasto.valor,
        vencimento: gasto.vencimento,
        pago: false,
      );
      expenses[index] = updated;
      return (somado: true, gasto: updated);
    }
    final saved = gasto.copyWith(id: expenses.length + 1);
    expenses.add(saved);
    return (somado: false, gasto: saved);
  }
}
