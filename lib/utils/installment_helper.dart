class InstallmentHelper {
  /// Divide um valor total em parcelas preservando os centavos no somatório final.
  static List<double> splitAmount(double totalAmount, int installmentCount) {
    if (installmentCount <= 0) {
      throw ArgumentError('installmentCount must be greater than zero');
    }

    return splitCentavos(
      (totalAmount * 100).round(),
      installmentCount,
    ).map((cents) => cents / 100).toList();
  }

  /// Divide um total em centavos; o resto vai para as primeiras parcelas.
  static List<int> splitCentavos(int totalInCents, int installmentCount) {
    if (installmentCount <= 0) {
      throw ArgumentError('installmentCount must be greater than zero');
    }
    final baseInstallment = totalInCents ~/ installmentCount;
    final remainder = totalInCents % installmentCount;
    return List.generate(
      installmentCount,
      (index) => baseInstallment + (index < remainder ? 1 : 0),
    );
  }

  /// Avança um período mês/ano considerando virada de ano.
  static ({int mes, int ano}) addMonths(int mes, int ano, int offset) {
    final totalMonths = (ano * 12) + (mes - 1) + offset;
    final newAno = totalMonths ~/ 12;
    final newMes = (totalMonths % 12) + 1;
    return (mes: newMes, ano: newAno);
  }
}
