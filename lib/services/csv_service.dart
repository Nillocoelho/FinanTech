import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import '../data/gastos_repository.dart';
import '../models/gasto.dart';
import '../utils/currency_helper.dart';
import 'backup_service.dart';

/// Resultado de uma importação de CSV.
class ImportacaoCsvResultado {
  const ImportacaoCsvResultado({
    required this.importados,
    required this.inalterados,
    required this.rejeitadas,
  });

  /// Valores mensais gravados (novos ou atualizados).
  final int importados;

  /// Valores que já estavam iguais no app (por exemplo, numa reimportação).
  final int inalterados;

  /// Células com valor ilegível, no formato `Origem (Mês/Ano): "texto"`.
  final List<String> rejeitadas;

  int get rejeitados => rejeitadas.length;

  /// Resumo para mostrar ao usuário.
  String get mensagem {
    final partes = <String>[
      '$importados ${importados == 1 ? 'valor importado' : 'valores importados'}',
      if (inalterados > 0)
        '$inalterados já ${inalterados == 1 ? 'estava' : 'estavam'} em dia',
      if (rejeitados > 0)
        '$rejeitados ${rejeitados == 1 ? 'célula ignorada' : 'células ignoradas'} por valor inválido',
    ];
    return '${partes.join(', ')}.';
  }
}

/// Serviço responsável por importar e exportar dados em formato CSV.
///
/// O formato CSV segue o padrão da planilha:
/// - 9 linhas em branco no início
/// - Linha com o título
/// - Linha com cabeçalho: "A quem:", meses de Abril a Abril do ano seguinte
/// - Linhas de dados: origem, valores em aberto por mês
/// - Linha de total no final
class CsvService {
  CsvService({
    BackupService? backupService,
    Future<Directory> Function()? directoryProvider,
  }) : _backupService = backupService ?? BackupService(),
       _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final BackupService _backupService;
  final Future<Directory> Function() _directoryProvider;
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  static const String titulo = 'Diazen - Gastos Mensais';

  // Meses na ordem do CSV (Abril a Abril do próximo ano)
  static const List<String> _mesesCsv = [
    'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro',
    'Outubro', 'Novembro', 'Dezembro', 'Janeiro', 'Fevereiro', 'Março', 'Abril',
  ];

  static const List<String> _nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  /// Mapeia o nome do mês para o número (1-12), sem diferenciar maiúsculas
  /// nem acento. Lança [FormatException] para nomes desconhecidos.
  static int _mesParaNumero(String mes) {
    final chave = mes.trim().toLowerCase().replaceAll('ç', 'c');
    for (var i = 0; i < _nomesMeses.length; i++) {
      if (_nomesMeses[i].toLowerCase().replaceAll('ç', 'c') == chave) {
        return i + 1;
      }
    }
    throw FormatException('Mês desconhecido no cabeçalho do CSV: "$mes".');
  }

  /// Decodifica os bytes do arquivo: UTF-8 e, se inválido, Latin-1
  /// (Windows-1252, padrão do Excel no Windows).
  static String decodificar(List<int> bytes) {
    String texto;
    try {
      texto = utf8.decode(bytes);
    } on FormatException {
      texto = latin1.decode(bytes, allowInvalid: true);
    }
    return texto.startsWith('﻿') ? texto.substring(1) : texto;
  }

  /// Escapa um campo CSV (aspas, vírgulas e quebras de linha).
  static String _campo(String valor) {
    final limpo = valor.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (limpo.contains(RegExp(r'[",]'))) {
      return '"${limpo.replaceAll('"', '""')}"';
    }
    return limpo;
  }

  static String _valor(int centavos) =>
      centavos == 0 ? '0' : '"${(centavos / 100).toStringAsFixed(2).replaceAll('.', ',')}"';

  /// Gera o conteúdo do CSV com os valores em aberto de Abril de [anoInicio]
  /// a Abril do ano seguinte.
  Future<String> gerarCsv({required int anoInicio}) async {
    final ano = anoInicio;
    final db = await _databaseHelper.database;
    final origens = (await db.rawQuery(
      'SELECT DISTINCT origem FROM ${DatabaseHelper.tableGastos} ORDER BY origem ASC',
    )).map((row) => row['origem'] as String).toList();
    final rows = await db.rawQuery(
      '''SELECT origem, mes, ano, SUM(valorCentavos) AS total
      FROM ${DatabaseHelper.tableGastos}
      WHERE pago = 0 AND ((ano = ? AND mes >= 4) OR (ano = ? AND mes <= 4))
      GROUP BY origem, ano, mes''',
      [ano, ano + 1],
    );

    // origem -> coluna (0 = Abril/ano, 12 = Abril/ano+1) -> centavos
    final dados = {for (final origem in origens) origem: List.filled(13, 0)};
    for (final row in rows) {
      final m = row['mes'] as int;
      final idx = row['ano'] == ano ? m - 4 : m + 8;
      dados[row['origem'] as String]![idx] += (row['total'] as num).toInt();
    }

    final buffer = StringBuffer();
    for (int i = 0; i < 9; i++) {
      buffer.writeln(',,,,,,,,,,,,,,,');
    }
    buffer.writeln(',,$titulo,,,,,,,,,,,,,');
    buffer.writeln(',,A quem:,${_mesesCsv.join(',')}');

    final totais = List.filled(13, 0);
    for (final origem in origens) {
      buffer.write(',,${_campo(origem)}');
      for (var i = 0; i < 13; i++) {
        final valor = dados[origem]![i];
        totais[i] += valor;
        buffer.write(',${_valor(valor)}');
      }
      buffer.writeln();
    }
    buffer.writeln(',,Total,${totais.map(_valor).join(',')}');
    return buffer.toString();
  }

  /// Exporta os gastos em aberto para um arquivo CSV no formato da planilha.
  ///
  /// [anoInicio] é o ano de início (Abril desse ano até Abril do próximo).
  /// Retorna o caminho do arquivo gerado.
  Future<String> exportarParaCsv({int? anoInicio}) async {
    final conteudo = await gerarCsv(
      anoInicio: anoInicio ?? DateTime.now().year,
    );
    final directory = await _directoryProvider();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/diazen_export_$timestamp.csv');
    await file.writeAsString(conteudo, encoding: utf8, flush: true);
    return file.path;
  }

  /// Importa gastos de um CSV no formato da planilha.
  ///
  /// Cada célula representa o total em aberto da origem no mês: o valor
  /// manual do app é **substituído** (não somado), descontando parcelas e
  /// recorrências já existentes. Reimportar o mesmo arquivo não muda nada.
  ///
  /// Tudo é gravado numa única transação, depois de um backup automático
  /// (desligue com [criarBackup] = false), e os lembretes são
  /// ressincronizados uma única vez no fim.
  Future<ImportacaoCsvResultado> importarDeCsv(
    String csvContent, {
    int? anoInicio,
    bool criarBackup = true,
  }) async {
    final ano = anoInicio ?? DateTime.now().year;
    final leitura = _ler(csvContent, ano);
    if (criarBackup && leitura.valores.isNotEmpty) {
      await _backupService.criarBackup();
    }

    final agora = DateTime.now().toIso8601String();
    final db = await _databaseHelper.database;
    final contagem = await db.transaction((txn) async {
      var importados = 0;
      var inalterados = 0;
      for (final item in leitura.valores) {
        switch (await _aplicar(txn, item, agora)) {
          case true:
            importados++;
          case false:
            inalterados++;
        }
      }
      return (importados: importados, inalterados: inalterados);
    });
    if (contagem.importados > 0) GastosRepository.notificarAlteracao();
    return ImportacaoCsvResultado(
      importados: contagem.importados,
      inalterados: contagem.inalterados,
      rejeitadas: leitura.rejeitadas,
    );
  }

  /// Retorna true se gravou, false se o app já tinha o valor.
  Future<bool> _aplicar(
    Transaction txn,
    ({String origem, int mes, int ano, int centavos}) item,
    String agora,
  ) async {
    final args = [item.origem, item.mes, item.ano];
    const filtro =
        'LOWER(origem) = LOWER(?) AND mes = ? AND ano = ? AND pago = 0';
    final planejado = await txn.rawQuery(
      '''SELECT COALESCE(SUM(valorCentavos), 0) AS total
      FROM ${DatabaseHelper.tableGastos} WHERE $filtro
      AND (parcelaGrupo IS NOT NULL OR recorrenciaId IS NOT NULL)''',
      args,
    );
    final alvo = item.centavos - (planejado.first['total'] as num).toInt();
    if (alvo <= 0) return false;

    final manuais = (await txn.query(
      DatabaseHelper.tableGastos,
      where: '$filtro AND parcelaGrupo IS NULL AND recorrenciaId IS NULL',
      whereArgs: args,
      orderBy: 'createdAt DESC, id DESC',
    )).map(Gasto.fromMap).toList();
    final outros = manuais
        .skip(1)
        .fold<int>(0, (soma, g) => soma + g.valorCentavos);
    final novo = alvo - outros;
    if (novo <= 0) return false;

    if (manuais.isEmpty) {
      await txn.insert(
        DatabaseHelper.tableGastos,
        Gasto(
          origem: item.origem,
          valorCentavos: novo,
          pago: false,
          mes: item.mes,
          ano: item.ano,
          createdAt: agora,
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return true;
    }
    final atual = manuais.first;
    if (atual.valorCentavos == novo) return false;
    await txn.update(
      DatabaseHelper.tableGastos,
      {'valorCentavos': novo, 'valor': novo / 100},
      where: 'id = ?',
      whereArgs: [atual.id],
    );
    return true;
  }

  /// Lê o CSV sem tocar no banco. Lança [FormatException] se o cabeçalho
  /// estiver ausente ou tiver um mês desconhecido.
  ({
    List<({String origem, int mes, int ano, int centavos})> valores,
    List<String> rejeitadas,
  })
  _ler(String csvContent, int ano) {
    final linhas = csvContent
        .split('\n')
        .map((linha) => linha.replaceAll('\r', ''))
        .toList();

    // Cabeçalho: a célula "A quem:" marca a coluna da origem.
    var linhaHeader = -1;
    var colunaOrigem = -1;
    for (var i = 0; i < linhas.length && linhaHeader < 0; i++) {
      final cells = _parseCsvLine(linhas[i]);
      for (var j = 0; j < cells.length; j++) {
        if (cells[j].trim().toLowerCase().startsWith('a quem')) {
          linhaHeader = i;
          colunaOrigem = j;
          break;
        }
      }
    }
    if (linhaHeader == -1) {
      throw const FormatException(
        'Formato CSV inválido: cabeçalho "A quem:" não encontrado.',
      );
    }

    // Coluna -> período. O ano avança quando a sequência de meses recomeça
    // (Dezembro -> Janeiro), e o primeiro mês pertence a [ano].
    final colunas = <int, ({int mes, int ano})>{};
    final headerCells = _parseCsvLine(linhas[linhaHeader]);
    var anoAtual = ano;
    int? anterior;
    for (var j = colunaOrigem + 1; j < headerCells.length; j++) {
      final nome = headerCells[j].trim();
      if (nome.isEmpty) continue;
      final mes = _mesParaNumero(nome);
      if (anterior != null && mes <= anterior) anoAtual++;
      anterior = mes;
      colunas[j] = (mes: mes, ano: anoAtual);
    }
    if (colunas.isEmpty) {
      throw const FormatException('O cabeçalho do CSV não tem meses.');
    }

    // Origens repetidas no arquivo têm os valores do mês somados.
    final acumulado = <String, ({String origem, int mes, int ano, int centavos})>{};
    final rejeitadas = <String>[];
    for (var i = linhaHeader + 1; i < linhas.length; i++) {
      if (linhas[i].trim().isEmpty) continue;
      final cells = _parseCsvLine(linhas[i]);
      if (colunaOrigem >= cells.length) continue;
      final origem = cells[colunaOrigem].trim();
      if (origem.toLowerCase() == 'total') break;
      if (origem.isEmpty) continue;

      for (final entrada in colunas.entries) {
        if (entrada.key >= cells.length) continue;
        final texto = cells[entrada.key].trim();
        if (texto.isEmpty) continue;
        final periodo = entrada.value;
        final centavos = CurrencyHelper.parseCentavos(texto);
        if (centavos == null) {
          rejeitadas.add(
            '$origem (${_nomesMeses[periodo.mes - 1]}/${periodo.ano}): "$texto"',
          );
          continue;
        }
        if (centavos == 0) continue;
        final chave = '${origem.toLowerCase()}|${periodo.ano}|${periodo.mes}';
        final existente = acumulado[chave];
        acumulado[chave] = (
          origem: existente?.origem ?? origem,
          mes: periodo.mes,
          ano: periodo.ano,
          centavos: (existente?.centavos ?? 0) + centavos,
        );
      }
    }
    return (valores: acumulado.values.toList(), rejeitadas: rejeitadas);
  }

  /// Faz o parse de uma linha CSV, respeitando aspas e aspas duplicadas ("").
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  /// Retorna o diretório de downloads (ou documentos como fallback)
  Future<Directory> getExportDirectory() async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return externalDir;
      }
    } catch (_) {}
    return await getApplicationDocumentsDirectory();
  }
}
