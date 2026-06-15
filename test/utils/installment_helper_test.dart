import 'package:finantech/utils/installment_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InstallmentHelper', () {
    test('splitAmount divide o valor preservando o total', () {
      final parcelas = InstallmentHelper.splitAmount(100.0, 3);

      expect(parcelas, [33.34, 33.33, 33.33]);
      expect(
        parcelas.fold<double>(0, (total, item) => total + item),
        closeTo(100.0, 0.001),
      );
    });

    test('splitAmount mantém centavos sem perder valor', () {
      final parcelas = InstallmentHelper.splitAmount(10.01, 2);

      expect(parcelas, [5.01, 5.00]);
      expect(
        parcelas.fold<double>(0, (total, item) => total + item),
        closeTo(10.01, 0.001),
      );
    });

    test('addMonths avança corretamente entre anos', () {
      expect(InstallmentHelper.addMonths(12, 2025, 1), (mes: 1, ano: 2026));
      expect(InstallmentHelper.addMonths(11, 2025, 3), (mes: 2, ano: 2026));
      expect(InstallmentHelper.addMonths(6, 2026, 0), (mes: 6, ano: 2026));
    });
  });
}
