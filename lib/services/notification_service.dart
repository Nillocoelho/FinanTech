import 'package:flutter/foundation.dart';
import '../data/database_helper.dart';
import '../models/gasto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço responsável por gerenciar notificações locais do aplicativo.
///
/// Agenda avisos na véspera do vencimento dos gastos em aberto.
class NotificationService {
  // Instância singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Plugin de notificações locais
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Chaves para salvar preferências
  static const String _reminderEnabledKey = 'monthly_reminder_enabled';
  static const String _reminderDayKey = 'monthly_reminder_day';
  static const String _reminderHourKey = 'monthly_reminder_hour';
  static const String _reminderMinuteKey = 'monthly_reminder_minute';

  // Valores padrão
  static const int defaultDay = 10;
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  // Canal de notificação Android
  static const String _channelId = 'finantech_due_reminders_v2';
  static const String _channelName = 'Lembretes Financeiros';
  static const String _channelDescription =
      'Avisos um dia antes do vencimento das contas';

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
    try {
      // Inicializa dados de timezone
      tz_data.initializeTimeZones();

      // Configuração para Android
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

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
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Solicita permissão de notificação (Android 13+)
      _initialized = true;
      await _requestNotificationPermission();
      await syncExpenseReminders();
    } catch (e) {
      // Ignora erros de inicialização - o app continua funcionando
      // ignore: avoid_print
      print('Erro ao inicializar notificações: $e');
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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted == false) {
        throw StateError(
          'Ative as notifica\u00e7\u00f5es do FinanTech nas configura\u00e7\u00f5es do celular.',
        );
      }
    }
  }

  /// Ativa e atualiza os avisos individuais de vencimento.
  Future<void> scheduleMonthlyReminder() async {
    await _setReminderEnabled(true);
    await syncExpenseReminders();
  }

  bool _initialized = false;

  static DateTime reminderDate(DateTime due, int hour, int minute) =>
      DateTime(due.year, due.month, due.day - 1, hour, minute);

  Future<void> syncExpenseReminders() async {
    if (!_initialized) return;
    // Remove também o antigo lembrete mensal durante a migração.
    await _notificationsPlugin.cancelAll();
    if (!await isReminderEnabled()) return;
    final db = await DatabaseHelper().database;
    final rows = await db.query(
      DatabaseHelper.tableGastos,
      where: 'pago = 0 AND vencimento IS NOT NULL',
    );
    final hour = await getReminderHour();
    final minute = await getReminderMinute();
    final now = DateTime.now();
    final upcoming =
        rows
            .map(Gasto.fromMap)
            .where(
              (g) => reminderDate(g.vencimento!, hour, minute).isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.vencimento!.compareTo(b.vencimento!));
    for (final gasto
        in (defaultTargetPlatform == TargetPlatform.iOS
            ? upcoming.take(60)
            : upcoming)) {
      final date = reminderDate(gasto.vencimento!, hour, minute);
      await _notificationsPlugin.zonedSchedule(
        id: gasto.id! + 100,
        title: 'Conta vence amanhã',
        body:
            '${gasto.origem}: R\$ ${gasto.valor.toStringAsFixed(2).replaceAll('.', ',')}. Vence amanhã.',
        // DateTime usa o fuso do celular, convertido para um instante UTC.
        scheduledDate: tz.TZDateTime.from(date, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Avisos um dia antes do vencimento das contas',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Atualiza os avisos sem comprometer a gravação dos gastos.
  Future<void> refreshAfterChange() async {
    try {
      await syncExpenseReminders();
    } catch (error) {
      debugPrint('Erro ao atualizar lembretes: $error');
    }
  }

  /// Cancela o lembrete mensal agendado.
  ///
  /// Remove qualquer notificação pendente com o ID do lembrete mensal.
  Future<void> cancelMonthlyReminder() async {
    await _notificationsPlugin.cancelAll();
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

  /// Obtém o dia configurado para o lembrete (padrão: 10)
  Future<int> getReminderDay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderDayKey) ?? defaultDay;
  }

  /// Obtém a hora configurada para o lembrete (padrão: 9)
  Future<int> getReminderHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderHourKey) ?? defaultHour;
  }

  /// Obtém os minutos configurados para o lembrete (padrão: 0)
  Future<int> getReminderMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderMinuteKey) ?? defaultMinute;
  }

  /// Salva o dia do lembrete
  Future<void> setReminderDay(int day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderDayKey, day);
  }

  /// Salva a hora do lembrete
  Future<void> setReminderHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderHourKey, hour);
  }

  /// Salva os minutos do lembrete
  Future<void> setReminderMinute(int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderMinuteKey, minute);
  }

  /// Salva todas as configurações de horário e reagenda o lembrete
  Future<void> updateReminderSchedule(int day, int hour, int minute) async {
    await setReminderDay(day);
    await setReminderHour(hour);
    await setReminderMinute(minute);

    // Se o lembrete está ativo, reagenda com as novas configurações
    final isEnabled = await isReminderEnabled();
    if (isEnabled) {
      await scheduleMonthlyReminder();
    }
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
    await _requestNotificationPermission();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _notificationsPlugin.show(
      id: 0, // ID reservado para o teste
      title: 'Teste de notificação',
      body: 'As notificações estão funcionando corretamente!',
      notificationDetails: notificationDetails,
    );
  }
}
