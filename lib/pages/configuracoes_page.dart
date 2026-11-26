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
/// Permite ao usuário configurar os lembretes de vencimento
/// e importar/exportar dados.
class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final NotificationService _notificationService = NotificationService();
  final CsvService _csvService = CsvService();
  final BackupService _backupService = BackupService();

  /// Operação de backup/planilha em andamento (desabilita os botões e mostra
  /// o indicador de progresso na própria página, sem diálogo modal).
  bool _busy = false;

  void _mensagem(String mensagem, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        action: action,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Executa [acao] com a página marcada como ocupada.
  Future<void> _ocupado(Future<void> Function() acao) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await acao();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _criarBackup() => _ocupado(() async {
    try {
      final path = await _backupService.criarBackup();
      if (!mounted) return;
      _mensagem(
        'Backup salvo neste aparelho. Compartilhe para guardar uma cópia fora dele.',
      );
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Backup completo dos gastos no Diazen',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      _mensagem('Não foi possível concluir o backup: $error');
    }
  });

  Future<void> _restaurarBackup({bool local = false}) => _ocupado(() async {
    try {
      String? path;
      if (local) {
        final files = await _backupService.listarBackupsLocais();
        if (!mounted) return;
        if (files.isEmpty) {
          _mensagem('Nenhum backup salvo neste aparelho.');
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
      final document = BackupService.decodeDocument(
        CsvService.decodificar(await File(path).readAsBytes()),
      );
      final gastos = document.gastos;
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
      await _backupService.restaurar(
        gastos,
        recorrencias: document.recorrencias,
      );
      await _carregarConfiguracoes();
      _mensagem('${gastos.length} gastos restaurados. Lembretes atualizados.');
    } catch (error) {
      _mensagem('Não foi possível restaurar o backup: $error');
    }
  });

  // Estado do switch de lembrete
  bool _lembreteAtivo = true;
  bool _isLoading = true;

  // Horário do aviso
  int _horaLembrete = NotificationService.defaultHour;
  int _minutoLembrete = NotificationService.defaultMinute;

  String get _horario =>
      '${_horaLembrete.toString().padLeft(2, '0')}:${_minutoLembrete.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  /// Carrega as configurações salvas.
  ///
  /// O switch só aparece ligado se o sistema também permitir notificações.
  Future<void> _carregarConfiguracoes() async {
    final isEnabled = await _notificationService.isReminderEnabled();
    final permitido = await _notificationService.notificacoesPermitidas();
    final hora = await _notificationService.getReminderHour();
    final minuto = await _notificationService.getReminderMinute();

    if (!mounted) return;
    setState(() {
      _lembreteAtivo = isEnabled && permitido != false;
      _horaLembrete = hora;
      _minutoLembrete = minuto;
      _isLoading = false;
    });
  }

  /// Ativa ou desativa os lembretes, pedindo a permissão ao ativar.
  Future<void> _toggleLembrete(bool value) async {
    setState(() => _lembreteAtivo = value);
    final ativo = await _notificationService.toggleReminder(value);
    if (!mounted) return;
    setState(() => _lembreteAtivo = ativo);

    if (value && !ativo) {
      _mensagem(
        'Sem permissão para notificações, os lembretes ficam desativados.',
        action: SnackBarAction(
          label: 'Abrir ajustes',
          onPressed: _notificationService.abrirConfiguracoesDoSistema,
        ),
      );
      return;
    }
    _mensagem(
      ativo
          ? 'Lembretes ativados para a véspera às $_horario'
          : 'Lembretes desativados.',
    );
  }

  /// Abre o seletor de horário do aviso
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
        _horaLembrete,
        _minutoLembrete,
      );
      if (_lembreteAtivo) {
        _mensagem('Lembrete atualizado: na véspera às $_horario');
      }
    }
  }

  /// Envia uma notificação de teste
  Future<void> _enviarNotificacaoTeste() async {
    await _notificationService.showTestNotification();
    _mensagem('Notificação de teste enviada!');
  }

  /// Exporta os dados para CSV
  Future<void> _exportarDados() async {
    final ano = await _selecionarAno(
      'Selecione o ano inicial para a exportação.\n'
      'O período será de Abril do ano selecionado até Abril do ano seguinte.',
    );
    if (ano == null) return;

    String? filePath;
    await _ocupado(() async {
      try {
        filePath = await _csvService.exportarParaCsv(anoInicio: ano);
      } catch (e) {
        _mensagem('Erro ao exportar: $e');
      }
    });
    final path = filePath;
    if (path == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartilhar arquivo'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(path)],
                    text: 'Planilha de gastos do Diazen',
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Abrir localização'),
              subtitle: Text(path, style: const TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                _mensagem('Arquivo salvo em: $path');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _selecionarAno(String explicacao) async {
    final anoAtual = DateTime.now().year;
    return await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ano de referência'),
        content: Text(explicacao),
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
    String conteudo;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result.isEmpty) return;
      final path = result.single.path;
      if (path == null) {
        _mensagem('Não foi possível acessar o arquivo escolhido.');
        return;
      }
      // UTF-8 ou, se inválido, Latin-1 (CSV salvo pelo Excel no Windows).
      conteudo = CsvService.decodificar(await File(path).readAsBytes());
    } catch (e) {
      _mensagem('Não foi possível ler o arquivo: $e');
      return;
    }
    if (!mounted) return;

    final ano = await _selecionarAno(
      'Selecione o ano inicial para a importação.\n'
      'Abril será associado ao ano selecionado, '
      'e Janeiro a Abril seguinte ao ano posterior. '
      'Os valores do arquivo substituem os do app; '
      'um backup é criado antes.',
    );
    if (ano == null) return;

    await _ocupado(() async {
      try {
        final resultado = await _csvService.importarDeCsv(
          conteudo,
          anoInicio: ano,
        );
        _mensagem(resultado.mensagem);
        if (resultado.rejeitados > 0 && mounted) {
          await _mostrarRejeitadas(resultado.rejeitadas);
        }
      } catch (e) {
        _mensagem('Erro ao importar: $e');
      }
    });
  }

  Future<void> _mostrarRejeitadas(List<String> rejeitadas) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${rejeitadas.length} valores não importados'),
      content: SingleChildScrollView(
        child: Text(
          'Estas células não têm um valor em reais válido e foram ignoradas:\n\n${rejeitadas.join('\n')}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SettingsContent(
              enabled: _lembreteAtivo,
              time: _horario,
              busy: _busy,
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
      _mensagem(error is StateError ? error.message : error.toString());
    }
  }
}
