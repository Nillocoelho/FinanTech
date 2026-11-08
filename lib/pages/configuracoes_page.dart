import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/notification_service.dart';
import '../services/csv_service.dart';
import '../services/backup_service.dart';
import '../widgets/settings_content.dart';

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
  final BackupService _backupService = BackupService();
  bool _backupBusy = false;

  void _mensagemBackup(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _criarBackup() async {
    setState(() => _backupBusy = true);
    try {
      final path = await _backupService.criarBackup();
      if (!mounted) return;
      _mensagemBackup(
        'Backup salvo neste aparelho. Compartilhe para guardar uma cópia fora dele.',
      );
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Backup completo dos gastos FinanTech',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      _mensagemBackup('Não foi possível concluir o backup: $error');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restaurarBackup({bool local = false}) async {
    setState(() => _backupBusy = true);
    try {
      String? path;
      if (local) {
        final files = await _backupService.listarBackupsLocais();
        if (!mounted) return;
        if (files.isEmpty) {
          _mensagemBackup('Nenhum backup salvo neste aparelho.');
          return;
        }
        path = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Backups neste aparelho'),
            children: files
                .map(
                  (file) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, file.path),
                    child: Text(file.path.split(Platform.pathSeparator).last),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        path = result.isEmpty ? null : result.single.path;
      }
      if (path == null) return;
      final gastos = BackupService.decode(await File(path).readAsString());
      if (!mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restaurar backup?'),
          content: Text(
            'Os gastos atuais serão substituídos pelos ${gastos.length} gastos deste backup, de todos os meses. Uma cópia dos dados atuais será salva em “Backups neste aparelho”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
      await _backupService.restaurar(gastos);
      await _carregarConfiguracoes();
      _mensagemBackup(
        '${gastos.length} gastos restaurados. Lembretes atualizados.',
      );
    } catch (error) {
      _mensagemBackup('Não foi possível restaurar o backup: $error');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

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

    if (!mounted) return;
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
                ? 'Lembretes ativados para a véspera às ${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}'
                : 'Lembretes desativados.',
          ),
          backgroundColor: value ? Colors.green : Colors.grey,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Abre o seletor de dia do mês em formato de calendário
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
        _diaLembrete,
        _horaLembrete,
        _minutoLembrete,
      );
      _mostrarSnackConfirmacao();
    }
  }

  void _mostrarSnackConfirmacao() {
    if (mounted && _lembreteAtivo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lembrete atualizado: na véspera às ${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}',
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
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
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
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(filePath)],
                        text: 'Planilha de gastos FinanTech',
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Abrir localização'),
                  subtitle: Text(
                    filePath,
                    style: const TextStyle(fontSize: 12),
                  ),
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
        try {
          Navigator.pop(context);
        } catch (_) {}
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
          'O período será de Abril do ano selecionado até Abril do ano seguinte.',
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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result.isEmpty) return;

      final file = File(result.single.path!);
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
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      final importados = await _csvService.importarDeCsv(
        content,
        anoInicio: ano,
      );

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
        try {
          Navigator.pop(context);
        } catch (_) {}
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
          'e Janeiro a Março ao ano seguinte.',
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

  @override
  Widget build(BuildContext context) {
    final time =
        '${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SettingsContent(
              enabled: _lembreteAtivo,
              time: time,
              busy: _backupBusy,
              onToggle: (value) =>
                  _runSettingAction(() => _toggleLembrete(value)),
              onTime: () => _runSettingAction(_selecionarHorario),
              onTest: () => _runSettingAction(_enviarNotificacaoTeste),
              onBackup: _criarBackup,
              onRestore: () => _restaurarBackup(),
              onLocal: () => _restaurarBackup(local: true),
              onExport: _exportarDados,
              onImport: _importarDados,
            ),
    );
  }

  Future<void> _runSettingAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      await _carregarConfiguracoes();
      _mensagemBackup(error.toString());
    }
  }
}
