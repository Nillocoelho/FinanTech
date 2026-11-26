/// Modelo que representa um gasto/dívida no sistema.
///
/// Cada gasto possui uma origem (a quem se deve), um valor,
/// um status de pagamento, e está associado a um mês/ano específico.
class Gasto {
  /// Identificador único do gasto (auto-incrementado pelo SQLite).
  ///
  /// Valores negativos indicam uma ocorrência de recorrência projetada em
  /// memória (ainda não gravada); o repositório grava a ocorrência quando
  /// alguma ação é feita sobre ela.
  final int? id;

  /// Origem da dívida (ex: "Santander", "Inter", "Pai")
  final String origem;

  /// Valor da dívida em centavos inteiros (evita erro de ponto flutuante).
  final int valorCentavos;

  /// Valor da dívida em reais (derivado de [valorCentavos]).
  double get valor => valorCentavos / 100;

  /// Indica se a dívida foi paga (true = paga, false = em aberto)
  final bool pago;

  /// Mês do gasto (1 a 12)
  final int mes;

  /// Ano do gasto (ex: 2025)
  final int ano;

  /// Data de criação no formato ISO8601 para ordenação
  final String createdAt;

  final DateTime? vencimento;
  final String categoria;
  final String? parcelaGrupo;
  final int? parcelaNumero;
  final int? parcelaTotal;
  final String? recorrenciaId;

  /// Joined from the recurring rule; not persisted in the expense row.
  final bool recorrenciaAtiva;

  bool get parcelado => parcelaGrupo != null;

  /// Ocorrência de recorrência calculada em memória, ainda não gravada.
  bool get projetado => id != null && id! < 0;

  bool vencidoEm(DateTime agora) {
    final data = vencimento;
    if (pago || data == null) return false;
    return DateTime(
      data.year,
      data.month,
      data.day,
    ).isBefore(DateTime(agora.year, agora.month, agora.day));
  }

  /// Converte reais para centavos, rejeitando valores não finitos.
  static int paraCentavos(double valor) {
    if (!valor.isFinite) throw ArgumentError.value(valor, 'valor');
    return (valor * 100).round();
  }

  /// Informe [valor] (reais) ou [valorCentavos]; os centavos têm prioridade.
  Gasto({
    this.id,
    this.vencimento,
    this.categoria = 'Sem categoria',
    this.parcelaGrupo,
    this.parcelaNumero,
    this.parcelaTotal,
    this.recorrenciaId,
    this.recorrenciaAtiva = true,
    required this.origem,
    double? valor,
    int? valorCentavos,
    required this.pago,
    required this.mes,
    required this.ano,
    required this.createdAt,
  }) : assert(valor != null || valorCentavos != null),
       valorCentavos = valorCentavos ?? paraCentavos(valor!);

  /// Lê os centavos de uma linha do banco ou de um backup.
  ///
  /// Backups antigos e bancos anteriores à v4 têm apenas `valor` (REAL).
  static int centavosDoMapa(Map<String, dynamic> map) {
    final centavos = map['valorCentavos'];
    if (centavos is int) return centavos;
    return paraCentavos((map['valor'] as num).toDouble());
  }

  /// Cria uma instância de [Gasto] a partir de um Map (vindo do SQLite)
  ///
  /// O campo 'pago' no SQLite é INTEGER (0 ou 1), então convertemos para bool.
  factory Gasto.fromMap(Map<String, dynamic> map) {
    return Gasto(
      id: map['id'] as int?,
      categoria: map['categoria'] as String? ?? 'Sem categoria',
      parcelaGrupo: map['parcelaGrupo'] as String?,
      parcelaNumero: map['parcelaNumero'] as int?,
      parcelaTotal: map['parcelaTotal'] as int?,
      recorrenciaId: map['recorrenciaId'] as String?,
      recorrenciaAtiva: map['recorrenciaAtiva'] != 0,
      vencimento: DateTime.tryParse(map['vencimento'] as String? ?? ''),
      origem: map['origem'] as String,
      valorCentavos: centavosDoMapa(map),
      pago: (map['pago'] as int) == 1, // Converte 0/1 para false/true
      mes: map['mes'] as int,
      ano: map['ano'] as int,
      createdAt: map['createdAt'] as String,
    );
  }

  /// Converte a instância de [Gasto] para um Map (para salvar no SQLite)
  ///
  /// O campo 'pago' é convertido de bool para INTEGER (0 ou 1).
  /// `valor` continua sendo gravado para que backups novos sigam legíveis
  /// por versões anteriores do app.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id, // Só inclui o id se não for null
      'origem': origem,
      'valor': valor,
      'valorCentavos': valorCentavos,
      'pago': pago ? 1 : 0, // Converte true/false para 1/0
      'mes': mes,
      'ano': ano,
      'createdAt': createdAt,
      'vencimento': vencimento?.toIso8601String(),
      'categoria': categoria,
      'parcelaGrupo': parcelaGrupo,
      'parcelaNumero': parcelaNumero,
      'parcelaTotal': parcelaTotal,
      'recorrenciaId': recorrenciaId,
    };
  }

  /// Cria uma cópia do [Gasto] com campos alterados
  ///
  /// Útil para atualizar o status de pagamento sem criar um novo objeto do zero.
  Gasto copyWith({
    int? id,
    String? origem,
    double? valor,
    int? valorCentavos,
    bool? pago,
    int? mes,
    int? ano,
    String? createdAt,
    DateTime? vencimento,
    String? categoria,
    String? parcelaGrupo,
    int? parcelaNumero,
    int? parcelaTotal,
    String? recorrenciaId,
    bool? recorrenciaAtiva,
  }) {
    return Gasto(
      id: id ?? this.id,
      categoria: categoria ?? this.categoria,
      parcelaGrupo: parcelaGrupo ?? this.parcelaGrupo,
      parcelaNumero: parcelaNumero ?? this.parcelaNumero,
      parcelaTotal: parcelaTotal ?? this.parcelaTotal,
      recorrenciaId: recorrenciaId ?? this.recorrenciaId,
      recorrenciaAtiva: recorrenciaAtiva ?? this.recorrenciaAtiva,
      vencimento: vencimento ?? this.vencimento,
      origem: origem ?? this.origem,
      valorCentavos:
          valorCentavos ??
          (valor != null ? paraCentavos(valor) : this.valorCentavos),
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
