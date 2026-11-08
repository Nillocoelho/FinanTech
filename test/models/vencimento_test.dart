import 'package:flutter_test/flutter_test.dart';
import 'package:finantech/models/gasto.dart';

void main() {
  final gasto = Gasto(origem: 'Conta', valor: 100, pago: false,
      mes: 11, ano: 2026, createdAt: '2026-11-03',
      vencimento: DateTime(2026, 11, 3, 9));

  test('due today is not overdue, regardless of the time', () {
    expect(gasto.vencidoEm(DateTime(2026, 11, 3, 23, 59)), isFalse);
    expect(gasto.vencidoEm(DateTime(2026, 11, 4)), isTrue);
    expect(gasto.vencidoEm(DateTime(2026, 11, 2)), isFalse);
  });

  test('paid and undated expenses are never overdue', () {
    expect(gasto.copyWith(pago: true).vencidoEm(DateTime(2027)), isFalse);
    final legacy = Gasto(origem: 'Antigo', valor: 10, pago: false,
        mes: 1, ano: 2020, createdAt: '2020-01-01');
    expect(legacy.vencidoEm(DateTime(2027)), isFalse);
  });
}
