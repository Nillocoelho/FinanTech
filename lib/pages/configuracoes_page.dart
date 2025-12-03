import 'package:flutter/material.dart';
import '../services/notification_service.dart';

/// Tela de configurações do aplicativo.
/// 
/// Permite ao usuário configurar preferências do app,
/// incluindo o lembrete mensal de revisão de gastos.
class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final NotificationService _notificationService = NotificationService();
  
  // Estado do switch de lembrete
  bool _lembreteAtivo = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  /// Carrega as configurações salvas
  Future<void> _carregarConfiguracoes() async {
    final isEnabled = await _notificationService.isReminderEnabled();
    setState(() {
      _lembreteAtivo = isEnabled;
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
              ? 'Lembrete mensal ativado! Você será notificado todo dia 10.'
              : 'Lembrete mensal desativado.',
          ),
          backgroundColor: value ? Colors.green : Colors.grey,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
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
                  subtitle: const Text(
                    'Receba uma notificação todo dia 10 às 09:00 '
                    'para revisar seus gastos do mês.',
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
                
                const Divider(),
                
                // Botão de teste de notificação
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Testar notificação'),
                  subtitle: const Text('Enviar uma notificação agora para testar'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _enviarNotificacaoTeste,
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
                
                // Informação adicional sobre o lembrete
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
                                'Dica',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'O lembrete é enviado todo dia 10 porque é uma boa '
                            'data para revisar os gastos do mês anterior e '
                            'planejar o mês atual.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Constrói o header de uma seção
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
}
