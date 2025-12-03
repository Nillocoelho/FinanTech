import 'package:flutter/material.dart';
import 'pages/gastos_page.dart';
import 'services/notification_service.dart';

/// Ponto de entrada do aplicativo FinanTech.
/// 
/// Este aplicativo permite controlar gastos mensais de forma simples,
/// registrando dívidas por origem e calculando totais em aberto.
void main() async {
  // Garante que o Flutter esteja inicializado antes de rodar o app
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa o serviço de notificações
  await NotificationService().initNotifications();
  
  runApp(const FinanTechApp());
}

/// Widget raiz do aplicativo.
/// 
/// Define o tema e a estrutura básica de navegação do app.
class FinanTechApp extends StatelessWidget {
  const FinanTechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Nome do app que aparece na lista de apps recentes
      title: 'FinanTech - Controle de Gastos',
      
      // Remove o banner de debug no canto superior direito
      debugShowCheckedModeBanner: false,
      
      // Configuração do tema claro
      theme: ThemeData(
        // Usa Material Design 3 (Material You)
        useMaterial3: true,
        
        // Esquema de cores baseado em uma semente (cor principal)
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        
        // Configuração da AppBar
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
        
        // Configuração dos Cards
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        
        // Configuração dos campos de entrada
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        
        // Configuração dos botões elevados
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      
      // Configuração do tema escuro
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      
      // Usa o tema escuro fixo
      themeMode: ThemeMode.dark,
      
      // Tela inicial do aplicativo
      home: GastosPage(),
    );
  }
}
