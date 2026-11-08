import 'package:flutter/material.dart';

import '../models/gasto.dart';
import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';

class FutureCommitments extends StatelessWidget {
  const FutureCommitments({super.key, required this.totals});
  final Map<DateTime, double> totals;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FinanceSection(
        title: 'Próximos meses',
        subtitle: 'Parcelas e contas recorrentes em aberto',
      ),
      Card(
        child: Column(
          children: totals.entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.key.month.toString().padLeft(2, '0')}/${entry.key.year}',
                          style: const TextStyle(color: FinanceColors.muted),
                        ),
                      ),
                      Text(
                        money(entry.value),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
}

class InstallmentDetails extends StatelessWidget {
  const InstallmentDetails({
    super.key,
    required this.expenses,
    required this.reference,
  });
  final List<Gasto> expenses;
  final Gasto reference;
  @override
  Widget build(BuildContext context) {
    final pending = expenses.where((g) => !g.pago).toList();
    final open = pending.fold<double>(0, (v, g) => v + g.valor);
    final removed = (reference.parcelaTotal! - expenses.length).clamp(0, 120);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        children: [
          Text(
            reference.origem,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Compra em ${reference.parcelaTotal} parcelas · ${reference.categoria}',
            style: const TextStyle(color: FinanceColors.muted),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Valor ainda em aberto',
                    style: TextStyle(color: FinanceColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    money(open),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${expenses.length - pending.length} ${expenses.length - pending.length == 1 ? 'paga' : 'pagas'} · ${pending.length} em aberto',
                    style: const TextStyle(color: FinanceColors.muted),
                  ),
                ],
              ),
            ),
          ),
          if (removed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '$removed parcelas foram excluídas. Os valores consideram apenas as parcelas cadastradas.',
                style: const TextStyle(color: FinanceColors.muted),
              ),
            ),
          const FinanceSection(title: 'Acompanhamento das parcelas'),
          ...expenses.map(
            (g) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                g.pago ? Icons.check_circle_outline : Icons.schedule,
                color: g.pago ? FinanceColors.green : FinanceColors.muted,
              ),
              title: Text(
                'Parcela ${g.parcelaNumero} de ${g.parcelaTotal}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${g.mes.toString().padLeft(2, '0')}/${g.ano} · ${g.pago ? 'Paga' : 'Em aberto'}',
              ),
              trailing: Text(
                money(g.valor),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
