import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço responsável por gerenciar notificações locais do aplicativo.
/// 
/// Este serviço permite agendar lembretes mensais para que o usuário
/// revise seus gastos no dia 10 de cada mês às 09:00.
class NotificationService {
  // Instância singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Plugin de notificações locais
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ID único para o lembrete mensal (usado para cancelar/atualizar)
  static const int _monthlyReminderId = 1;

  // Chave para salvar preferência do lembrete
  static const String _reminderEnabledKey = 'monthly_reminder_enabled';

  // Canal de notificação Android
  static const String _channelId = 'finantech_reminders';
  static const String _channelName = 'Lembretes Financeiros';
  static const String _channelDescription = 
      'Notificações de lembrete para revisar gastos mensais';

  /// Inicializa o serviço de notificações.
  /// 
  /// Deve ser chamado no início do app (main.dart) antes de usar
  /// qualquer outro método deste serviço.
  /// 
  /// Configura:
  /// - Timezone local para agendamentos
  /// - Plugin de notificações com configurações Android/iOS
  /// - Solicita permissão de notificação (Android 13+)
  Future<void> initNotifications() async {
    // Inicializa dados de timezone
    tz_data.initializeTimeZones();

    // Configuração para Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuração para iOS (opcional, mas bom ter)
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Configurações gerais de inicialização
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Inicializa o plugin
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Solicita permissão de notificação (Android 13+)
    await _requestNotificationPermission();

    // Verifica se o lembrete está ativo e agenda se necessário
    final isEnabled = await isReminderEnabled();
    if (isEnabled) {
      await scheduleMonthlyReminder();
    }
  }

  /// Callback executado quando o usuário toca na notificação.
  /// 
  /// Pode ser usado para navegar para uma tela específica.
  void _onNotificationTapped(NotificationResponse response) {
    // Por enquanto, apenas abre o app (comportamento padrão)
    // Pode ser expandido para navegar para uma tela específica
  }

  /// Solicita permissão de notificação ao usuário (Android 13+).
  /// 
  /// Em versões anteriores do Android, a permissão é concedida automaticamente.
  Future<void> _requestNotificationPermission() async {
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  /// Agenda o lembrete mensal para o dia 10 às 09:00.
  /// 
  /// O lembrete é configurado para repetir todo mês no mesmo dia e horário.
  /// Se a data atual já passou do dia 10, agenda para o próximo mês.
  /// 
  /// Usa [matchDateTimeComponents] com [DateTimeComponents.dayOfMonthAndTime]
  /// para garantir repetição mensal.
  Future<void> scheduleMonthlyReminder() async {
    // Cancela qualquer lembrete anterior antes de agendar novo
    await cancelMonthlyReminder();

    // Calcula a próxima data do dia 10 às 09:00
    final scheduledDate = _getNextReminderDate();

    // Detalhes da notificação para Android
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      // Som padrão do sistema
      playSound: true,
      // Vibração padrão
      enableVibration: true,
    );

    // Detalhes da notificação para iOS
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Detalhes combinados
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Agenda a notificação mensal recorrente
    await _notificationsPlugin.zonedSchedule(
      _monthlyReminderId,
      'Lembrete financeiro',
      'Você tem gastos para revisar neste mês. Abra o app e confira.',
      scheduledDate,
      notificationDetails,
      // Configuração para repetir mensalmente no dia 10 às 09:00
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    // Salva preferência como ativa
    await _setReminderEnabled(true);
  }

  /// Calcula a próxima data para o lembrete (dia 10 às 09:00).
  /// 
  /// Se hoje já passou do dia 10, retorna o dia 10 do próximo mês.
  /// Caso contrário, retorna o dia 10 do mês atual.
  tz.TZDateTime _getNextReminderDate() {
    final now = tz.TZDateTime.now(tz.local);
    
    // Data alvo: dia 10 às 09:00 do mês atual
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      10, // dia 10
      9,  // 09:00
      0,  // 00 minutos
    );

    // Se a data já passou, agenda para o próximo mês
    if (scheduledDate.isBefore(now)) {
      // Avança para o próximo mês
      if (now.month == 12) {
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year + 1,
          1, // Janeiro
          10,
          9,
          0,
        );
      } else {
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month + 1,
          10,
          9,
          0,
        );
      }
    }

    return scheduledDate;
  }

  /// Cancela o lembrete mensal agendado.
  /// 
  /// Remove qualquer notificação pendente com o ID do lembrete mensal.
  Future<void> cancelMonthlyReminder() async {
    await _notificationsPlugin.cancel(_monthlyReminderId);
    await _setReminderEnabled(false);
  }

  /// Verifica se o lembrete mensal está ativo.
  /// 
  /// Lê a preferência salva no SharedPreferences.
  /// Retorna true por padrão se nunca foi configurado.
  Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // Retorna true por padrão (lembrete ativado na primeira execução)
    return prefs.getBool(_reminderEnabledKey) ?? true;
  }

  /// Salva o estado do lembrete nas preferências.
  Future<void> _setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminderEnabledKey, enabled);
  }

  /// Alterna o estado do lembrete mensal.
  /// 
  /// Se [enabled] for true, agenda o lembrete.
  /// Se [enabled] for false, cancela o lembrete.
  Future<void> toggleReminder(bool enabled) async {
    if (enabled) {
      await scheduleMonthlyReminder();
    } else {
      await cancelMonthlyReminder();
    }
  }

  /// Envia uma notificação de teste imediata.
  /// 
  /// Útil para verificar se as notificações estão funcionando.
  /// Não afeta o lembrete mensal agendado.
  Future<void> showTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0, // ID diferente do lembrete mensal
      'Teste de notificação',
      'As notificações estão funcionando corretamente!',
      notificationDetails,
    );
  }
}
