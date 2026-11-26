import 'package:flutter/services.dart';

/// Formatador de entrada para valores monetários em Real brasileiro.
///
/// Formata automaticamente o valor digitado como moeda brasileira,
/// com separador de milhares (.) e decimais (,).
///
/// Exemplo: digitar "12345" resulta em "123,45"
class CurrencyInputFormatter extends TextInputFormatter {
  /// Quantidade máxima de dígitos aceitos (centavos incluídos).
  static const int maxDigitos = 11;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove tudo que não é dígito
    final String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Até 11 dígitos (R$ 999.999.999,99) para evitar estouro e valores colados
    // por engano; acima disso mantém o texto anterior.
    if (newText.length > maxDigitos) return oldValue;

    // Se estiver vazio, retorna vazio
    if (newText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Converte para número (centavos)
    final int value = int.parse(newText);

    // Formata como moeda (divide por 100 para ter os centavos)
    final String formatted = _formatCurrency(value);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Formata um valor inteiro (em centavos) para string de moeda
  String _formatCurrency(int valueInCents) {
    // Divide por 100 para obter o valor em reais
    final double value = valueInCents / 100;

    // Separa parte inteira e decimal
    final String valueStr = value.toStringAsFixed(2);
    final List<String> parts = valueStr.split('.');
    final String intPart = parts[0];
    final String decPart = parts[1];

    // Adiciona separador de milhares na parte inteira
    String formattedInt = '';
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        formattedInt = '.$formattedInt';
      }
      formattedInt = intPart[i] + formattedInt;
      count++;
    }

    return '$formattedInt,$decPart';
  }
}

/// Classe utilitária para conversão de valores monetários
class CurrencyHelper {
  /// Converte uma string formatada como moeda para double
  ///
  /// Exemplo: "1.234,56" -> 1234.56
  static double parseFromCurrency(String text) {
    final centavos = parseCentavos(text);
    return centavos == null ? 0.0 : centavos / 100;
  }

  static final RegExp _comMilhar = RegExp(r'^\d{1,3}(\.\d{3})+(,\d{1,2})?$');
  static final RegExp _semMilhar = RegExp(r'^\d+(,\d{1,2})?$');
  static final RegExp _pontoDecimal = RegExp(r'^\d+\.\d{1,2}$');

  /// Converte um texto em reais para centavos inteiros.
  ///
  /// Aceita "1.234,56", "1234,56", "R$ 50,00", "50" e também "1234.56"
  /// (ponto decimal com até duas casas, comum em planilhas exportadas).
  /// Retorna `null` quando o texto não é um valor monetário válido.
  static int? parseCentavos(String text) {
    final t = text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[\s ]'), '')
        .replaceAll('"', '');
    if (t.isEmpty) return null;
    String inteiro;
    String decimal;
    if (_comMilhar.hasMatch(t) || _semMilhar.hasMatch(t)) {
      final partes = t.replaceAll('.', '').split(',');
      inteiro = partes[0];
      decimal = partes.length > 1 ? partes[1] : '';
    } else if (_pontoDecimal.hasMatch(t)) {
      final partes = t.split('.');
      inteiro = partes[0];
      decimal = partes[1];
    } else {
      return null;
    }
    if (inteiro.length > CurrencyInputFormatter.maxDigitos) return null;
    return int.parse(inteiro) * 100 + int.parse(decimal.padRight(2, '0'));
  }

  /// Formata centavos inteiros como moeda brasileira (sem símbolo R$).
  static String formatCentavos(int centavos) {
    final negativo = centavos < 0;
    final abs = centavos.abs();
    final intPart = (abs ~/ 100).toString();
    final decPart = (abs % 100).toString().padLeft(2, '0');
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
      buffer.write(intPart[i]);
    }
    return '${negativo ? '-' : ''}$buffer,$decPart';
  }

  /// Formata um double para string de moeda brasileira (sem símbolo R$)
  ///
  /// Exemplo: 1234.56 -> "1.234,56"
  static String formatToCurrency(double value) {
    final String valueStr = value.toStringAsFixed(2);
    final List<String> parts = valueStr.split('.');
    final String intPart = parts[0];
    final String decPart = parts[1];

    // Adiciona separador de milhares
    String formattedInt = '';
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        formattedInt = '.$formattedInt';
      }
      formattedInt = intPart[i] + formattedInt;
      count++;
    }

    return '$formattedInt,$decPart';
  }

  /// Formata um double para string de moeda com símbolo R$
  static String formatWithSymbol(double value) {
    return 'R\$ ${formatToCurrency(value)}';
  }
}
