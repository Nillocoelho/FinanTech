import 'package:flutter/services.dart';

/// Formatador de entrada para valores monetários em Real brasileiro.
/// 
/// Formata automaticamente o valor digitado como moeda brasileira,
/// com separador de milhares (.) e decimais (,).
/// 
/// Exemplo: digitar "12345" resulta em "123,45"
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove tudo que não é dígito
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    // Se estiver vazio, retorna vazio
    if (newText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    
    // Converte para número (centavos)
    int value = int.parse(newText);
    
    // Formata como moeda (divide por 100 para ter os centavos)
    String formatted = _formatCurrency(value);
    
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
  
  /// Formata um valor inteiro (em centavos) para string de moeda
  String _formatCurrency(int valueInCents) {
    // Divide por 100 para obter o valor em reais
    double value = valueInCents / 100;
    
    // Separa parte inteira e decimal
    String valueStr = value.toStringAsFixed(2);
    List<String> parts = valueStr.split('.');
    String intPart = parts[0];
    String decPart = parts[1];
    
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
    if (text.isEmpty) return 0.0;
    
    // Remove pontos de milhar e troca vírgula por ponto
    String normalized = text
        .replaceAll('.', '')  // Remove separador de milhares
        .replaceAll(',', '.'); // Troca vírgula decimal por ponto
    
    return double.tryParse(normalized) ?? 0.0;
  }
  
  /// Formata um double para string de moeda brasileira (sem símbolo R$)
  /// 
  /// Exemplo: 1234.56 -> "1.234,56"
  static String formatToCurrency(double value) {
    String valueStr = value.toStringAsFixed(2);
    List<String> parts = valueStr.split('.');
    String intPart = parts[0];
    String decPart = parts[1];
    
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
