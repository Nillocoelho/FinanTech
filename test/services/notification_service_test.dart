import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finantech/services/notification_service.dart';
import 'package:finantech/models/gasto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initializes and sends test notifications through the updated Android API',
    () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      SharedPreferences.setMockInitialValues({
        'monthly_reminder_enabled': false,
      });
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'initialize' ||
                    call.method == 'requestNotificationsPermission'
                ? true
                : null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = NotificationService();
      await service.initNotifications();
      await service.showTestNotification();
      expect(
        calls.map((call) => call.method),
        containsAllInOrder([
          'initialize',
          'requestNotificationsPermission',
          'cancelAll',
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
