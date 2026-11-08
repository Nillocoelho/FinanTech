import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finantech/main.dart';
import 'package:finantech/pages/gastos_page.dart';

import 'support/finance_fixture.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadFinanceFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'mes_selecionado': 11,
      'ano_selecionado': 2026,
    });
  });

  Future<void> open(WidgetTester tester, PreviewRepository repository) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanTechApp(
        home: GastosPage(repository: repository, now: () => fixtureNow),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overview shows actual totals and an overdue alert', (
    tester,
  ) async {
    await open(tester, PreviewRepository());
    expect(find.text('R\$ 2.736,80'), findsOneWidget);
    expect(find.text('R\$ 3.377,05'), findsOneWidget);
    expect(find.text('R\$ 640,25'), findsWidgets);
    expect(find.text('1 conta vencida'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and status filters compose without changing totals', (
    tester,
  ) async {
    await open(tester, PreviewRepository());
    await tester.tap(find.text('Lançamentos').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nubank');
    await tester.pumpAndSettle();
    expect(find.text('Nubank'), findsNWidgets(2));
    expect(find.text('Aluguel'), findsNothing);
    await tester.tap(find.text('Pagas'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma conta encontrada'), findsOneWidget);
    await tester.ensureVisible(find.text('Limpar filtros'));
    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Aluguel'), findsOneWidget);
  });

  testWidgets('payment action updates totals and removes the overdue alert', (
    tester,
  ) async {
    final repo = PreviewRepository();
    await open(tester, repo);
    final action = find.byTooltip('Ações de Aluguel');
    await tester.scrollUntilVisible(
      action,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como pago'));
    await tester.pumpAndSettle();
    expect(repo.expenses.first.pago, isTrue);
    expect(find.text('1 conta vencida'), findsNothing);
    expect(find.text('R\$ 1.286,80'), findsOneWidget);
  });

  testWidgets('empty and error states offer a next action', (tester) async {
    await open(tester, PreviewRepository(empty: true));
    expect(find.text('Seu mês começa aqui'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await open(tester, PreviewRepository(fail: true));
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor validates amount, name and due date', (tester) async {
    await open(tester, PreviewRepository());
    await tester.tap(find.byTooltip('Adicionar gasto'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Adicionar lançamento'));
    await tester.tap(find.text('Adicionar lançamento'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
    expect(find.text('Informe o nome da conta.'), findsOneWidget);
    expect(find.text('Selecione o vencimento.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new installments preserve the total and cross the year boundary',
    (tester) async {
      final repo = PreviewRepository();
      await open(tester, repo);
      await tester.tap(find.byTooltip('Adicionar gasto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '10000');
      await tester.enterText(find.byType(TextFormField).at(1), 'Curso');
      await tester.tap(find.text('Selecione uma data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(2), '3');
      await tester.ensureVisible(find.text('Adicionar lançamento'));
      await tester.tap(find.text('Adicionar lançamento'));
      await tester.pumpAndSettle();
      final created = repo.expenses.where((g) => g.origem == 'Curso').toList();
      expect(created.length, 3);
      expect(
        created.map((g) => g.valor).reduce((a, b) => a + b),
        closeTo(100, 0.001),
      );
      expect(created.last.mes, 1);
      expect(created.last.ano, 2027);
      expect(created.last.vencimento, DateTime(2027, 1, 15));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deletion requires confirmation', (tester) async {
    final repo = PreviewRepository();
    await open(tester, repo);
    await tester.tap(find.text('Lançamentos').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ações de Aluguel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir lançamento'));
    await tester.pumpAndSettle();
    expect(repo.expenses.length, 5);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.expenses.length, 5);
    await tester.tap(find.byTooltip('Ações de Aluguel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir lançamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(repo.expenses.length, 4);
    expect(repo.expenses.any((g) => g.origem == 'Aluguel'), isFalse);
  });

  testWidgets('layout remains usable at 360px with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanTechApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 900),
            textScaler: TextScaler.linear(1.4),
          ),
          child: GastosPage(
            repository: PreviewRepository(),
            now: () => fixtureNow,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
