import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finantech/main.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/pages/gastos_page.dart';

import 'support/finance_fixture.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadFinanceFonts);
  testWidgets('capture categories, installments and future commitments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'mes_selecionado': 11,
      'ano_selecionado': 2026,
    });
    final repo = PreviewRepository(empty: true);
    Gasto expense(String name, double value, String category, int day) => Gasto(
      origem: name,
      valor: value,
      categoria: category,
      pago: false,
      mes: 11,
      ano: 2026,
      createdAt: '2026-11-01',
      vencimento: DateTime(2026, 11, day),
    );
    repo.expenses.add(
      expense('Internet', 119.90, 'Assinaturas', 12).copyWith(id: 1),
    );
    await repo.criarParcelamento(expense('Notebook', 3000, 'Compras', 15), 10);
    await repo.criarRecorrencia(
      expense('Aluguel', 1450, 'Moradia', 5),
      now: fixtureNow,
    );
    Widget frame() => RepaintBoundary(
      key: const ValueKey('planning-preview'),
      child: FinanTechApp(
        home: GastosPage(repository: repo, now: () => fixtureNow),
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('planning-preview')),
        matchesGoldenFile('../artifacts/versao-2.0/previews/planejamento-$name.png'),
      );
    }

    await tester.pumpWidget(frame());
    await capture('01-inicio');
    await tester.tap(find.text('Contas').last);
    await capture('02-categorias-e-parcelas');
    final action = find.byTooltip('Ações de Notebook');
    await tester.scrollUntilVisible(
      action,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver parcelamento'));
    await capture('03-acompanhamento-parcelas');
    await tester.tap(find.text('Marcar parcela 1 como paga'));
    await capture('04-parcela-paga');
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Futuro').last);
    await capture('05-proximos-meses');
    await tester.tap(find.bySemanticsLabel(RegExp('^Fevereiro 2027')));
    await capture('06-proximos-meses-fevereiro');
    await tester.tap(find.byTooltip('Novo lançamento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '300000');
    await tester.enterText(find.byType(TextFormField).at(1), 'Geladeira');
    await tester.tap(find.text('Parcelada'));
    await capture('07-novo-parcelado');
  });
}
