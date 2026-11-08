import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finantech/main.dart';
import 'package:finantech/pages/gastos_page.dart';
import 'package:finantech/pages/configuracoes_page.dart';
import 'package:finantech/widgets/expense_editor.dart';

import 'support/finance_fixture.dart';
import 'support/load_fonts.dart';

// Capture the actual Flutter screens. Fixtures never enter the production app.
void main() {
  setUpAll(loadFinanceFonts);
  testWidgets('export mobile refactor screens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'mes_selecionado': 11,
      'ano_selecionado': 2026,
    });
    final repo = PreviewRepository();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('preview')),
        matchesGoldenFile(
          '../artifacts/refatoracao-finantech/previews/$name.png',
        ),
      );
    }

    Widget frame(Widget home) => RepaintBoundary(
      key: const ValueKey('preview'),
      child: FinanTechApp(home: home),
    );
    await tester.pumpWidget(
      frame(GastosPage(repository: repo, now: () => fixtureNow)),
    );
    await capture('01-visao-geral');
    await tester.tap(find.text('Lançamentos').last);
    await capture('02-lancamentos');
    await tester.tap(find.byTooltip('Adicionar gasto'));
    await capture('03-novo-lancamento');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(frame(const ConfiguracoesPage()));
    await capture('04-ajustes');
    await tester.drag(find.byType(ListView).first, const Offset(0, -530));
    await capture('08-ajustes-dados');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      frame(
        GastosPage(
          repository: PreviewRepository(empty: true),
          now: () => fixtureNow,
        ),
      ),
    );
    await capture('05-estado-vazio');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      frame(
        Scaffold(
          body: ExpenseEditor(
            period: fixtureNow,
            origins: const ['Aluguel', 'Nubank'],
            expense: repo.expenses.first,
          ),
        ),
      ),
    );
    await capture('06-editar-lancamento');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      frame(GastosPage(repository: repo, now: () => fixtureNow)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver resumo'));
    await capture('07-resumo-mensal');
  });
}
