import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/notification_service.dart';
import '../services/csv_service.dart';

/// Tela de configurações do aplicativo.
/// 
/// Permite ao usuário configurar preferências do app,
/// incluindo o lembrete mensal de revisão de gastos
/// e importação/exportação de dados.
class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final NotificationService _notificationService = NotificationService();
  final CsvService _csvService = CsvService();
  
  // Estado do switch de lembrete
  bool _lembreteAtivo = true;
  bool _isLoading = true;
  
  // Configurações de dia e hora
  int _diaLembrete = NotificationService.defaultDay;
  int _horaLembrete = NotificationService.defaultHour;
  int _minutoLembrete = NotificationService.defaultMinute;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  /// Carrega as configurações salvas
  Future<void> _carregarConfiguracoes() async {
    final isEnabled = await _notificationService.isReminderEnabled();
    final dia = await _notificationService.getReminderDay();
    final hora = await _notificationService.getReminderHour();
    final minuto = await _notificationService.getReminderMinute();
    
    setState(() {
      _lembreteAtivo = isEnabled;
      _diaLembrete = dia;
      _horaLembrete = hora;
      _minutoLembrete = minuto;
      _isLoading = false;
    });
  }

  /// Alterna o estado do lembrete mensal
  Future<void> _toggleLembrete(bool value) async {
    setState(() => _lembreteAtivo = value);
    
    await _notificationService.toggleReminder(value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? 'Lembrete ativado para dia $_diaLembrete às ${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}'
              : 'Lembrete mensal desativado.',
          ),
          backgroundColor: value ? Colors.green : Colors.grey,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Abre o seletor de dia do mês em formato de calendário
  Future<void> _selecionarDia() async {
    final dia = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecione o dia'),
        content: SizedBox(
          width: 280,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 28,
            itemBuilder: (context, index) {
              final d = index + 1;
              final isSelected = d == _diaLembrete;
              return InkWell(
                onTap: () => Navigator.pop(context, d),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$d',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    
    if (dia != null && dia != _diaLembrete) {
      setState(() => _diaLembrete = dia);
      await _notificationService.updateReminderSchedule(
        _diaLembrete, _horaLembrete, _minutoLembrete
      );
      _mostrarSnackConfirmacao();
    }
  }

  /// Abre o seletor de horário
  Future<void> _selecionarHorario() async {
    final horario = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _horaLembrete, minute: _minutoLembrete),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (horario != null) {
      setState(() {
        _horaLembrete = horario.hour;
        _minutoLembrete = horario.minute;
      });
      await _notificationService.updateReminderSchedule(
        _diaLembrete, _horaLembrete, _minutoLembrete
      );
      _mostrarSnackConfirmacao();
    }
  }

  void _mostrarSnackConfirmacao() {
    if (mounted && _lembreteAtivo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lembrete atualizado: dia $_diaLembrete às ${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Envia uma notificação de teste
  Future<void> _enviarNotificacaoTeste() async {
    await _notificationService.showTestNotification();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notificação de teste enviada!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Exporta os dados para CSV
  Future<void> _exportarDados() async {
    try {
      // Pergunta o ano de referência
      final anoAtual = DateTime.now().year;
      final ano = await _selecionarAnoExportacao(anoAtual);
      
      if (ano == null) return;
      
      // Mostra loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }
      
      final filePath = await _csvService.exportarParaCsv(anoInicio: ano);
      
      if (mounted) Navigator.pop(context); // Fecha loading
      
      // Oferece opções: compartilhar ou salvar
      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Compartilhar arquivo'),
                  onTap: () async {
                    Navigator.pop(context);
                    await Share.shareXFiles([XFile(filePath)], 
                      text: 'Planilha de gastos FinanTech');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Abrir localização'),
                  subtitle: Text(filePath, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Arquivo salvo em: $filePath'),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        try { Navigator.pop(context); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int?> _selecionarAnoExportacao(int anoAtual) async {
    return await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ano de referência'),
        content: const Text(
          'Selecione o ano inicial para a exportação.\n'
          'O período será de Abril do ano selecionado até Abril do ano seguinte.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ...List.generate(3, (i) {
            final ano = anoAtual - 1 + i;
            return TextButton(
              onPressed: () => Navigator.pop(context, ano),
              child: Text('$ano'),
            );
          }),
        ],
      ),
    );
  }

  /// Importa dados de um arquivo CSV
  Future<void> _importarDados() async {
    try {
      // Abre o seletor de arquivo
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      
      // Pergunta o ano de referência
      final anoAtual = DateTime.now().year;
      final ano = await _selecionarAnoImportacao(anoAtual);
      
      if (ano == null) return;
      
      // Mostra loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }
      
      final importados = await _csvService.importarDeCsv(content, anoInicio: ano);
      
      if (mounted) Navigator.pop(context); // Fecha loading
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$importados gastos importados com sucesso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        try { Navigator.pop(context); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int?> _selecionarAnoImportacao(int anoAtual) async {
    return await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ano de referência'),
        content: const Text(
          'Selecione o ano inicial para a importação.\n'
          'Abril será associado ao ano selecionado, '
          'e Janeiro a Março ao ano seguinte.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ...List.generate(3, (i) {
            final ano = anoAtual - 1 + i;
            return TextButton(
              onPressed: () => Navigator.pop(context, ano),
              child: Text('$ano'),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horarioFormatado = '${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Seção de Notificações
                _buildSectionHeader('Notificações'),
                
                // Switch do lembrete mensal
                SwitchListTile(
                  title: const Text('Lembrete mensal de contas'),
                  subtitle: Text(
                    _lembreteAtivo 
                      ? 'Ativo: dia $_diaLembrete às $horarioFormatado'
                      : 'Desativado',
                  ),
                  value: _lembreteAtivo,
                  onChanged: _toggleLembrete,
                  secondary: Icon(
                    _lembreteAtivo 
                      ? Icons.notifications_active 
                      : Icons.notifications_off,
                    color: _lembreteAtivo 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.grey,
                  ),
                ),
                
                // Configuração de dia
                ListTile(
                  enabled: _lembreteAtivo,
                  leading: Icon(Icons.calendar_today,
                    color: _lembreteAtivo ? null : Colors.grey),
                  title: const Text('Dia do lembrete'),
                  subtitle: Text('Dia $_diaLembrete de cada mês'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _lembreteAtivo ? _selecionarDia : null,
                ),
                
                // Configuração de horário
                ListTile(
                  enabled: _lembreteAtivo,
                  leading: Icon(Icons.access_time,
                    color: _lembreteAtivo ? null : Colors.grey),
                  title: const Text('Horário do lembrete'),
                  subtitle: Text(horarioFormatado),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _lembreteAtivo ? _selecionarHorario : null,
                ),
                
                const Divider(),
                
                // Botão de teste de notificação
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Testar notificação'),
                  subtitle: const Text('Enviar uma notificação agora'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _enviarNotificacaoTeste,
                ),
                
                const Divider(height: 32),
                
                // Seção de Dados
                _buildSectionHeader('Importação / Exportação'),
                
                // Exportar para CSV
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Exportar para planilha'),
                  subtitle: const Text('Gerar arquivo CSV no formato da planilha'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportarDados,
                ),
                
                // Importar de CSV
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Importar de planilha'),
                  subtitle: const Text('Importar gastos de um arquivo CSV'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importarDados,
                ),
                
                const Divider(height: 32),
                
                // Seção Sobre
                _buildSectionHeader('Sobre'),
                
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('FinanTech'),
                  subtitle: Text('Versão 1.0.0\nControle de gastos mensais'),
                  isThreeLine: true,
                ),
                
                const SizedBox(height: 24),
                
                // Informação sobre o formato CSV
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Formato CSV',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'O arquivo CSV segue o formato da planilha com:\n'
                            '• Colunas: Origem, Abril, Maio, ... Abril\n'
                            '• Valores em formato brasileiro (vírgula)\n'
                            '• Linha de total no final',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
