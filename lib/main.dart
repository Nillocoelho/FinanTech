import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/gastos_page.dart';
import 'services/notification_service.dart';
import 'ui/brand.dart';
import 'ui/finance_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinanTechApp());
  // As notificações iniciam em segundo plano, sem pedir permissão (isso é
  // feito ao ativar os lembretes) e sem atrasar a primeira tela.
  unawaited(_iniciarLembretes());
}

AppLifecycleListener? _lifecycle;

Future<void> _iniciarLembretes() async {
  final notifications = NotificationService();
  await notifications.initNotifications();
  notifications.agendarSincronizacao();
  // Ao voltar ao app, refaz o plano: vencimentos podem ter passado ou o
  // usuário pode ter mudado a permissão nas configurações do sistema.
  _lifecycle ??= AppLifecycleListener(
    onResume: notifications.agendarSincronizacao,
  );
}

class FinanTechApp extends StatelessWidget {
  const FinanTechApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kAppName,
    debugShowCheckedModeBanner: false,
    theme: financeTheme(),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home ?? const GastosPage(),
  );
}
