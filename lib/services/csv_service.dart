import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../data/gastos_repository.dart';
import '../models/gasto.dart';

/// Serviço responsável por importar e exportar dados em formato CSV.
/// 
/// O formato CSV segue o padrão da planilha do usuário:
/// - 9 linhas em branco no início
/// - Linha com título "Danillo Gastos Mensais"
/// - Linha com cabeçalho: "A quem:", meses...
/// - Linhas de dados: origem, valores por mês
/// - Linha de total no final
class CsvService {
  final GastosRepository _repository = GastosRepository();

  // Meses na ordem do CSV (Abril a Abril do próximo ano)
  static const List<String> _mesesCsv = [
    'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro',
    'Outubro', 'Novembro', 'Dezembro', 'Janeiro', 'Fevereiro', 'Março', 'Abril'
  ];

  /// Mapeia o nome do mês para o número (1-12)
  static int _mesParaNumero(String mes) {
    final meses = {
      'Janeiro': 1, 'Fevereiro': 2, 'Março': 3, 'Abril': 4,
      'Maio': 5, 'Junho': 6, 'Julho': 7, 'Agosto': 8,
      'Setembro': 9, 'Outubro': 10, 'Novembro': 11, 'Dezembro': 12,
    };
    return meses[mes.trim()] ?? 1;
  }

  /// Mapeia o número do mês para o nome
  static String _numeroParaMes(int mes) {
    final meses = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return meses[mes];
  }

  /// Exporta todos os gastos para um arquivo CSV no formato da planilha.
  /// 
  /// [anoInicio] é o ano de início (Abril desse ano até Março do próximo + Abril)
  /// Retorna o caminho do arquivo gerado.
  Future<String> exportarParaCsv({int? anoInicio}) async {
    // Usa o ano atual como padrão
    final ano = anoInicio ?? DateTime.now().year;
    
    // Obtém todas as origens distintas
    final origens = await _repository.getOrigensDistintas();
    
    // Mapa para armazenar valores: origem -> mês -> valor
    final Map<String, Map<String, double>> dados = {};
    
    // Inicializa o mapa com todas as origens
    for (final origem in origens) {
      dados[origem] = {};
      for (final mes in _mesesCsv) {
        dados[origem]![mes] = 0.0;
      }
    }
    
    // Busca os gastos de cada mês
    // Abril a Dezembro do ano inicial
    for (int m = 4; m <= 12; m++) {
      final gastos = await _repository.getGastosDoMes(m, ano);
      final mesNome = _numeroParaMes(m);
      for (final gasto in gastos) {
        if (!gasto.pago) { // Apenas gastos não pagos
          dados[gasto.origem] ??= {};
          dados[gasto.origem]![mesNome] = 
              (dados[gasto.origem]![mesNome] ?? 0) + gasto.valor;
        }
      }
    }
    
    // Janeiro a Abril do próximo ano
    for (int m = 1; m <= 4; m++) {
      final gastos = await _repository.getGastosDoMes(m, ano + 1);
      final mesNome = _numeroParaMes(m);
      for (final gasto in gastos) {
        if (!gasto.pago) {
          dados[gasto.origem] ??= {};
          if (m == 4) {
            // Abril do próximo ano vai na última coluna
            dados[gasto.origem]!['Abril'] = 
                (dados[gasto.origem]!['Abril'] ?? 0) + gasto.valor;
          } else {
            dados[gasto.origem]![mesNome] = 
                (dados[gasto.origem]![mesNome] ?? 0) + gasto.valor;
          }
        }
      }
    }
    
    // Constrói o CSV
    final buffer = StringBuffer();
    
    // 9 linhas em branco
    for (int i = 0; i < 9; i++) {
      buffer.writeln(',,,,,,,,,,,,,,,');
    }
    
    // Linha do título
    buffer.writeln(',,Danillo Gastos Mensais,,,,,,,,,,,,,');
    
    // Linha do cabeçalho
    buffer.write(',,A quem:');
    for (final mes in _mesesCsv) {
      buffer.write(',$mes ');
    }
    buffer.writeln();
    
    // Linhas de dados
    final Map<String, double> totaisPorMes = {};
    for (final mes in _mesesCsv) {
      totaisPorMes[mes] = 0.0;
    }
    
    for (final origem in origens) {
      buffer.write(',,$origem');
      for (final mes in _mesesCsv) {
        final valor = dados[origem]?[mes] ?? 0.0;
        totaisPorMes[mes] = (totaisPorMes[mes] ?? 0) + valor;
        // Formata o valor no padrão brasileiro
        final valorStr = valor == 0 
            ? '0' 
            : valor.toStringAsFixed(2).replaceAll('.', ',');
        buffer.write(',"$valorStr"');
      }
      buffer.writeln();
    }
    
    // Linha de total
    buffer.write(',,Total');
    for (final mes in _mesesCsv) {
      final total = totaisPorMes[mes] ?? 0.0;
      final totalStr = total == 0 
          ? '0' 
          : total.toStringAsFixed(2).replaceAll('.', ',');
      buffer.write(',"$totalStr"');
    }
    buffer.writeln();
    
    // Salva o arquivo
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${directory.path}/finantech_export_$timestamp.csv';
    final file = File(filePath);
    await file.writeAsString(buffer.toString(), encoding: utf8);
    
    return filePath;
  }

  /// Importa gastos de um arquivo CSV no formato da planilha.
  /// 
  /// [csvContent] é o conteúdo do arquivo CSV.
  /// [anoInicio] é o ano de referência para Abril (início do período).
  /// Retorna o número de gastos importados.
  Future<int> importarDeCsv(String csvContent, {int? anoInicio}) async {
    final ano = anoInicio ?? DateTime.now().year;
    int importados = 0;
    
    // Divide o conteúdo em linhas
    final linhas = csvContent.split('\n');
    
    // Encontra a linha do cabeçalho (contém "A quem:")
    int linhaHeader = -1;
    for (int i = 0; i < linhas.length; i++) {
      if (linhas[i].contains('A quem:')) {
        linhaHeader = i;
        break;
      }
    }
    
    if (linhaHeader == -1) {
      throw Exception('Formato CSV inválido: cabeçalho não encontrado');
    }
    
    // Parse do cabeçalho para obter os meses
    final headerCells = _parseCsvLine(linhas[linhaHeader]);
    final meses = <String>[];
    bool foundAQuem = false;
    for (final cell in headerCells) {
      if (cell.trim().toLowerCase().contains('a quem')) {
        foundAQuem = true;
        continue;
      }
      if (foundAQuem && cell.trim().isNotEmpty) {
        meses.add(cell.trim());
      }
    }
    
    // Processa as linhas de dados (após o cabeçalho, até encontrar "Total")
    for (int i = linhaHeader + 1; i < linhas.length; i++) {
      final linha = linhas[i].trim();
      if (linha.isEmpty) continue;
      if (linha.toLowerCase().contains('total')) break;
      
      final cells = _parseCsvLine(linha);
      
      // Encontra a origem (primeira célula não vazia após as colunas vazias)
      String? origem;
      int startIdx = 0;
      for (int j = 0; j < cells.length; j++) {
        if (cells[j].trim().isNotEmpty && 
            !cells[j].contains(',') && 
            double.tryParse(cells[j].replaceAll(',', '.').replaceAll('"', '')) == null) {
          origem = cells[j].trim();
          startIdx = j + 1;
          break;
        }
      }
      
      if (origem == null || origem.toLowerCase() == 'total') continue;
      
      // Processa os valores para cada mês
      int mesIdx = 0;
      for (int j = startIdx; j < cells.length && mesIdx < meses.length; j++) {
        final valorStr = cells[j].trim().replaceAll('"', '');
        if (valorStr.isEmpty) {
          mesIdx++;
          continue;
        }
        
        // Converte o valor
        final valor = double.tryParse(valorStr.replaceAll(',', '.')) ?? 0.0;
        
        if (valor > 0) {
          // Determina o mês e ano
          final mesNome = meses[mesIdx];
          final mesNum = _mesParaNumero(mesNome);
          
          // Abril a Dezembro = ano inicial, Janeiro a Abril = ano + 1
          int anoGasto = ano;
          if (mesNum >= 1 && mesNum <= 4 && mesIdx >= 9) {
            // Janeiro a Abril após Dezembro = próximo ano
            anoGasto = ano + 1;
          } else if (mesNum >= 1 && mesNum <= 3) {
            anoGasto = ano + 1;
          }
          
          // Verifica se já existe
          final existe = await _repository.existeGastoComOrigem(
            origem, mesNum, anoGasto
          );
          
          if (!existe) {
            // Cria o gasto
            final gasto = Gasto(
              origem: origem,
              valor: valor,
              pago: false,
              mes: mesNum,
              ano: anoGasto,
              createdAt: DateTime.now().toIso8601String(),
            );
            
            await _repository.insertGasto(gasto);
            importados++;
          }
        }
        mesIdx++;
      }
    }
    
    return importados;
  }

  /// Faz o parse de uma linha CSV, respeitando valores entre aspas
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    
    // Adiciona o último campo
    result.add(buffer.toString());
    
    return result;
  }

  /// Retorna o diretório de downloads (ou documentos como fallback)
  Future<Directory> getExportDirectory() async {
    try {
      // Tenta obter o diretório de downloads externo (Android)
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return externalDir;
      }
    } catch (_) {}
    
    // Fallback para documentos
    return await getApplicationDocumentsDirectory();
  }
}
