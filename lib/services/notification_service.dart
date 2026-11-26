import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/database_helper.dart';
import '../data/gastos_repository.dart';
import '../models/gasto.dart';
import '../utils/currency_helper.dart';

/// Lembrete calculado para um gasto em aberto.
typedef LembretePlanejado = ({Gasto gasto, DateTime data, bool noDia});

/// Serviço responsável por gerenciar notificações locais do aplicativo.
///
/// Agenda avisos na véspera do vencimento dos gastos em aberto. A
/// sincronização é disparada pelas alterações do [GastosRepository], com
/// debounce, e nunca bloqueia a interface.
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
  static const String _reminderHourKey = 'monthly_reminder_hour';
  static const String _reminderMinuteKey = 'monthly_reminder_minute';

  // Valores padrão
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  /// Teto de lembretes agendados em todas as plataformas (o iOS aceita 64 e
  /// alguns fabricantes Android cortam alarmes em excesso).
  static const int maxLembretes = 50;

  /// Intervalo de agrupamento das sincronizações.
  static const Duration debounce = Duration(milliseconds: 300);

  /// Id reservado para a notificação de teste; lembretes usam id do gasto + 100.
  static const int _testId = 0;

  // Canal de notificação Android
  static const String _channelId = 'finantech_due_reminders_v2';
  static const String _channelName = 'Lembretes do Diazen';
  static const String _channelDescription =
      'Avisos um dia antes do vencimento das contas';

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        // O corpo mostra o valor da conta: na tela de bloqueio, só o aviso.
        visibility: NotificationVisibility.private,
      );

  bool _initialized = false;
  StreamSubscription<void>? _changesSubscription;
  Timer? _debounceTimer;
  Future<void>? _syncEmAndamento;
  bool _syncPendente = false;

  /// Inicializa o plugin de notificações.
  ///
  /// Não pede permissão nem sincroniza: a permissão é pedida ao ativar os
  /// lembretes e a sincronização é agendada por [agendarSincronizacao].
  /// Usa apenas o fuso UTC do pacote timezone (os horários são convertidos
  /// do fuso do aparelho para um instante UTC), sem carregar a base de fusos.
  Future<void> initNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _initialized = true;
      _changesSubscription ??= GastosRepository.changes.listen(
        (_) => agendarSincronizacao(),
      );
    } catch (e) {
      // Ignora erros de inicialização - o app continua funcionando
      debugPrint('Erro ao inicializar notificações: $e');
    }
  }

  /// Callback executado quando o usuário toca na notificação.
  void _onNotificationTapped(NotificationResponse response) {
    // Por enquanto, apenas abre o app (comportamento padrão)
  }

  /// Pede a permissão de notificação e informa se ela está concedida.
  Future<bool> solicitarPermissao() async {
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted == false) return false;
      return await androidPlugin.areNotificationsEnabled() ?? granted ?? true;
    }
    final iosPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      return await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  /// Informa se o sistema permite exibir notificações, sem pedir permissão.
  /// Retorna `null` quando a plataforma não informa.
  Future<bool?> notificacoesPermitidas() async {
    try {
      return await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  /// Abre as configurações de notificação do app no sistema.
  Future<void> abrirConfiguracoesDoSistema() async {
    await _notificationsPlugin.openAppNotificationSettings();
  }

  /// Data do aviso: véspera do vencimento no horário configurado.
  static DateTime reminderDate(DateTime due, int hour, int minute) =>
      DateTime(due.year, due.month, due.day - 1, hour, minute);

  /// Calcula os próximos lembretes, em ordem, limitados a [limite].
  ///
  /// Se a véspera já passou mas o horário do dia do vencimento ainda não,
  /// o aviso é marcado para o próprio dia do vencimento.
  static List<LembretePlanejado> planejarLembretes(
    Iterable<Gasto> gastos,
    DateTime now,
    int hour,
    int minute, {
    int limite = maxLembretes,
  }) {
    final planejados = <LembretePlanejado>[];
    for (final gasto in gastos) {
      final due = gasto.vencimento;
      if (gasto.pago || due == null || gasto.id == null || gasto.projetado) {
        continue;
      }
      final vespera = reminderDate(due, hour, minute);
      if (vespera.isAfter(now)) {
        planejados.add((gasto: gasto, data: vespera, noDia: false));
        continue;
      }
      final noDia = DateTime(due.year, due.month, due.day, hour, minute);
      if (noDia.isAfter(now)) {
        planejados.add((gasto: gasto, data: noDia, noDia: true));
      }
    }
    planejados.sort((a, b) => a.data.compareTo(b.data));
    return planejados.take(limite).toList();
  }

  /// Agenda uma sincronização com debounce, sem esperar o resultado.
  void agendarSincronizacao() {
    if (!_initialized) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(refreshAfterChange()));
  }

  /// Sincroniza os lembretes; chamadas concorrentes são agrupadas.
  Future<void> syncExpenseReminders() async {
    if (!_initialized) return;
    if (_syncEmAndamento != null) {
      _syncPendente = true;
      return _syncEmAndamento;
    }
    final completer = Completer<void>();
    _syncEmAndamento = completer.future;
    try {
      do {
        _syncPendente = false;
        await _sincronizar();
      } while (_syncPendente);
      completer.complete();
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      _syncEmAndamento = null;
    }
    return completer.future;
  }

  Future<void> _sincronizar() async {
    final enabled = await isReminderEnabled();
    final plano = enabled ? await _planoAtual() : const <LembretePlanejado>[];
    final ids = {for (final item in plano) item.gasto.id! + 100};

    // Cancela só os pendentes que saíram do plano; notificações já exibidas
    // e a de teste não são tocadas.
    List<PendingNotificationRequest> pendentes;
    try {
      pendentes = await _notificationsPlugin.pendingNotificationRequests();
    } catch (error) {
      debugPrint('Erro ao listar lembretes pendentes: $error');
      pendentes = const [];
    }
    for (final pendente in pendentes) {
      if (pendente.id == _testId || ids.contains(pendente.id)) continue;
      try {
        await _notificationsPlugin.cancel(id: pendente.id);
      } catch (error) {
        debugPrint('Erro ao cancelar lembrete ${pendente.id}: $error');
      }
    }

    for (final item in plano) {
      try {
        await _agendar(item);
      } catch (error) {
        // Um lembrete com problema não impede os demais.
        debugPrint('Erro ao agendar lembrete ${item.gasto.id}: $error');
      }
    }
  }

  Future<List<LembretePlanejado>> _planoAtual() async {
    final hour = await getReminderHour();
    final minute = await getReminderMinute();
    final now = DateTime.now();
    final ontem = DateTime(now.year, now.month, now.day - 1);
    final db = await DatabaseHelper().database;
    // Só os próximos vencimentos em aberto, já ordenados pelo banco.
    final rows = await db.query(
      DatabaseHelper.tableGastos,
      where: 'pago = 0 AND vencimento IS NOT NULL AND vencimento >= ?',
      whereArgs: [ontem.toIso8601String()],
      orderBy: 'vencimento',
      limit: maxLembretes * 4,
    );
    return planejarLembretes(rows.map(Gasto.fromMap), now, hour, minute);
  }

  Future<void> _agendar(LembretePlanejado item) async {
    final gasto = item.gasto;
    final valor = CurrencyHelper.formatCentavos(gasto.valorCentavos);
    await _notificationsPlugin.zonedSchedule(
      id: gasto.id! + 100,
      title: item.noDia ? 'Conta vence hoje' : 'Conta vence amanhã',
      body:
          '${gasto.origem}: R\$ $valor. ${item.noDia ? 'Vence hoje.' : 'Vence amanhã.'}',
      // DateTime usa o fuso do celular, convertido para um instante UTC.
      scheduledDate: tz.TZDateTime.from(item.data, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: _androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Atualiza os avisos sem comprometer a gravação dos gastos.
  Future<void> refreshAfterChange() async {
    try {
      await syncExpenseReminders();
    } catch (error) {
      debugPrint('Erro ao atualizar lembretes: $error');
    }
  }

  /// Verifica se os lembretes estão ativos (padrão: true).
  Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reminderEnabledKey) ?? true;
  }

  /// Salva o estado do lembrete nas preferências.
  Future<void> _setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminderEnabledKey, enabled);
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

  /// Salva o horário dos avisos e ressincroniza se estiverem ativos.
  Future<void> updateReminderSchedule(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderHourKey, hour);
    await prefs.setInt(_reminderMinuteKey, minute);
    if (await isReminderEnabled()) agendarSincronizacao();
  }

  /// Ativa ou desativa os lembretes.
  ///
  /// Ao ativar, pede a permissão; se negada, os lembretes continuam
  /// desativados e o retorno é `false`. Retorna o estado final.
  Future<bool> toggleReminder(bool enabled) async {
    if (enabled && !await solicitarPermissao()) {
      await _setReminderEnabled(false);
      return false;
    }
    await _setReminderEnabled(enabled);
    agendarSincronizacao();
    return enabled;
  }

  /// Envia uma notificação de teste imediata.
  ///
  /// Lança [StateError] se a permissão for negada.
  Future<void> showTestNotification() async {
    if (!await solicitarPermissao()) {
      throw StateError(
        'Ative as notificações do Diazen nas configurações do celular.',
      );
    }
    await _notificationsPlugin.show(
      id: _testId,
      title: 'Teste de notificação',
      body: 'As notificações estão funcionando corretamente!',
      notificationDetails: const NotificationDetails(
        android: _androidDetails,
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}
