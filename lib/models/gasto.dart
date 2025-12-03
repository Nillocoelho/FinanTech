/// Modelo que representa um gasto/dívida no sistema.
/// 
/// Cada gasto possui uma origem (a quem se deve), um valor,
/// um status de pagamento, e está associado a um mês/ano específico.
class Gasto {
  /// Identificador único do gasto (auto-incrementado pelo SQLite)
  final int? id;
  
  /// Origem da dívida (ex: "Santander", "Inter", "Pai")
  final String origem;
  
  /// Valor da dívida em reais
  final double valor;
  
  /// Indica se a dívida foi paga (true = paga, false = em aberto)
  final bool pago;
  
  /// Mês do gasto (1 a 12)
  final int mes;
  
  /// Ano do gasto (ex: 2025)
  final int ano;
  
  /// Data de criação no formato ISO8601 para ordenação
  final String createdAt;

  Gasto({
    this.id,
    required this.origem,
    required this.valor,
    required this.pago,
    required this.mes,
    required this.ano,
    required this.createdAt,
  });

  /// Cria uma instância de [Gasto] a partir de um Map (vindo do SQLite)
  /// 
  /// O campo 'pago' no SQLite é INTEGER (0 ou 1), então convertemos para bool.
  factory Gasto.fromMap(Map<String, dynamic> map) {
    return Gasto(
      id: map['id'] as int?,
      origem: map['origem'] as String,
      valor: (map['valor'] as num).toDouble(),
      pago: (map['pago'] as int) == 1, // Converte 0/1 para false/true
      mes: map['mes'] as int,
      ano: map['ano'] as int,
      createdAt: map['createdAt'] as String,
    );
  }

  /// Converte a instância de [Gasto] para um Map (para salvar no SQLite)
  /// 
  /// O campo 'pago' é convertido de bool para INTEGER (0 ou 1).
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id, // Só inclui o id se não for null
      'origem': origem,
      'valor': valor,
      'pago': pago ? 1 : 0, // Converte true/false para 1/0
      'mes': mes,
      'ano': ano,
      'createdAt': createdAt,
    };
  }

  /// Cria uma cópia do [Gasto] com campos alterados
  /// 
  /// Útil para atualizar o status de pagamento sem criar um novo objeto do zero.
  Gasto copyWith({
    int? id,
    String? origem,
    double? valor,
    bool? pago,
    int? mes,
    int? ano,
    String? createdAt,
  }) {
    return Gasto(
      id: id ?? this.id,
      origem: origem ?? this.origem,
      valor: valor ?? this.valor,
      pago: pago ?? this.pago,
      mes: mes ?? this.mes,
      ano: ano ?? this.ano,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Gasto(id: $id, origem: $origem, valor: $valor, pago: $pago, mes: $mes, ano: $ano)';
  }
}
