import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:finantech/data/database_helper.dart';
import 'package:finantech/services/notification_service.dart';
import 'package:finantech/models/gasto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late Directory directory;
  late List<MethodCall> calls;
  var pendentes = <Map<String, Object?>>[];
  var falharAgendamento = <int>{};

  setUpAll(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('diazen-notif-test-');
    await databaseFactory.setDatabasesPath(directory.path);
  });
  tearDownAll(() async {
    await DatabaseHelper().close();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    calls = [];
    pendentes = [];
    falharAgendamento = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
            case 'requestNotificationsPermission':
            case 'areNotificationsEnabled':
              return true;
            case 'pendingNotificationRequests':
              return pendentes;
            case 'zonedSchedule':
              final id = (call.arguments as Map)['id'] as int;
              if (falharAgendamento.contains(id)) {
                throw PlatformException(code: 'erro');
              }
              return null;
          }
          return null;
        });
    final db = await DatabaseHelper().database;
    await db.delete(DatabaseHelper.tableGastos);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'initialization does not prompt for permission; test notification does',
    () async {
      SharedPreferences.setMockInitialValues({
        'monthly_reminder_enabled': false,
      });
      final service = NotificationService();
      await service.initNotifications();
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestNotificationsPermission')),
      );
      await service.showTestNotification();
      expect(
        calls.map((call) => call.method),
        containsAllInOrder([
          'initialize',
          'requestNotificationsPermission',
          'show',
        ]),
      );
      final arguments = calls.last.arguments as Map;
      expect(arguments['id'], 0);
      expect(
        arguments['platformSpecifics']['channelId'],
        'finantech_due_reminders_v2',
      );
    },
  );

  test('reminder crosses month and year boundaries at the configured time', () {
    expect(
      NotificationService.reminderDate(DateTime(2027, 1, 1), 9, 30),
      DateTime(2026, 12, 31, 9, 30),
    );
    expect(
      NotificationService.reminderDate(DateTime(2028, 3, 1), 8, 0),
      DateTime(2028, 2, 29, 8),
    );
  });

  Gasto conta(int id, DateTime due, {bool pago = false}) => Gasto(
    id: id,
    origem: 'Conta $id',
    valor: 10,
    pago: pago,
    mes: due.month,
    ano: due.year,
    createdAt: '2026-11-01',
    vencimento: due,
  );

  test('plan is capped, ordered and skips paid or past bills', () {
    final now = DateTime(2026, 11, 10, 12);
    final gastos = [
      for (var i = 0; i < 200; i++)
        conta(i + 1, DateTime(2026, 11, 12).add(Duration(days: 199 - i))),
      conta(500, DateTime(2026, 11, 20), pago: true),
      conta(501, DateTime(2026, 11, 1)),
    ];
    final plano = NotificationService.planejarLembretes(gastos, now, 9, 0);
    expect(plano.length, NotificationService.maxLembretes);
    expect(plano.first.data, DateTime(2026, 11, 11, 9));
    for (var i = 1; i < plano.length; i++) {
      expect(plano[i].data.isAfter(plano[i - 1].data), isTrue);
    }
    expect(plano.map((p) => p.gasto.id), isNot(contains(500)));
    expect(plano.map((p) => p.gasto.id), isNot(contains(501)));
  });

  test('when the eve has passed, the reminder moves to the due day', () {
    final now = DateTime(2026, 11, 10, 10);
    final plano = NotificationService.planejarLembretes(
      [conta(1, DateTime(2026, 11, 11)), conta(2, DateTime(2026, 11, 10))],
      now,
      18,
      0,
    );
    expect(plano.map((p) => (p.gasto.id, p.data, p.noDia)), unorderedEquals([
      (2, DateTime(2026, 11, 10, 18), true),
      (1, DateTime(2026, 11, 10, 18), false),
    ]));
    final tarde = NotificationService.planejarLembretes(
      [conta(1, DateTime(2026, 11, 11))],
      DateTime(2026, 11, 10, 19),
      18,
      0,
    );
    expect(tarde.single.noDia, isTrue);
    expect(tarde.single.data, DateTime(2026, 11, 11, 18));
  });

  test(
    'sync schedules at most 50, cancels only stale pending ids and survives a failing item',
    () async {
      SharedPreferences.setMockInitialValues({
        'monthly_reminder_enabled': true,
      });
      final db = await DatabaseHelper().database;
      final hoje = DateTime.now();
      for (var i = 1; i <= 80; i++) {
        await db.insert(
          DatabaseHelper.tableGastos,
          conta(i, DateTime(hoje.year, hoje.month, hoje.day + 2 + i)).toMap(),
        );
      }
      pendentes = [
        {'id': 0, 'title': 'teste', 'body': '', 'payload': null},
        {'id': 101, 'title': 'mantido', 'body': '', 'payload': null},
        {'id': 9999, 'title': 'obsoleto', 'body': '', 'payload': null},
      ];
      falharAgendamento = {101};
      final service = NotificationService();
      await service.initNotifications();
      calls.clear();
      await service.syncExpenseReminders();

      final metodos = calls.map((c) => c.method).toList();
      expect(metodos, isNot(contains('cancelAll')));
      final cancelados = calls
          .where((c) => c.method == 'cancel')
          .map((c) => (c.arguments as Map)['id'])
          .toList();
      expect(cancelados, [9999]);
      final agendados = calls.where((c) => c.method == 'zonedSchedule');
      expect(agendados.length, NotificationService.maxLembretes);
      expect(
        agendados.map((c) => (c.arguments as Map)['id']),
        containsAll([101, 102, 150]),
      );
      final android =
          (agendados.last.arguments as Map)['platformSpecifics'] as Map;
      // NotificationVisibility.private
      expect(android['visibility'], 0);
    },
  );

  test(
    'due date survives storage and payment changes; legacy rows remain valid',
    () {
      final legacy = <String, dynamic>{
        'id': 7,
        'origem': 'Conta',
        'valor': 100.0,
        'pago': 0,
        'mes': 11,
        'ano': 2026,
        'createdAt': '2026-11-03',
      };
      expect(Gasto.fromMap(legacy).vencimento, isNull);
      final due = DateTime(2026, 11, 20);
      final gasto = Gasto.fromMap(legacy).copyWith(vencimento: due);
      final restored = Gasto.fromMap(gasto.toMap()).copyWith(pago: true);
      expect(restored.vencimento, due);
      expect(restored.pago, isTrue);
    },
  );
}
