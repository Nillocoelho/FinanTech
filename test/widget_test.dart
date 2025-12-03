import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:finantech/main.dart';
import 'package:finantech/pages/gastos_page.dart';

void main() {
  testWidgets('App deve carregar corretamente', (WidgetTester tester) async {
    await tester.pumpWidget(const FinanTechApp());
    
    // Verifica se o título está presente
    expect(find.text('Gastos Mensais'), findsOneWidget);
    
    // Verifica se o AppBar está presente
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('GastosPage deve ser uma StatefulWidget', (WidgetTester tester) async {
    expect(const GastosPage(), isA<StatefulWidget>());
  });
}
