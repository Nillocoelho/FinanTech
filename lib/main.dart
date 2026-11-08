import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/gastos_page.dart';
import 'services/notification_service.dart';
import 'ui/finance_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initNotifications();
  runApp(const FinanTechApp());
}

class FinanTechApp extends StatelessWidget {
  const FinanTechApp({super.key, this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FinanTech',
    debugShowCheckedModeBanner: false,
    theme: financeTheme(),
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home ?? const GastosPage(),
  );
}
