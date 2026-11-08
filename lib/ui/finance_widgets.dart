import 'package:flutter/material.dart';

import '../models/gasto.dart';
import '../utils/currency_helper.dart';
import 'finance_theme.dart';

String money(double value) => 'R\$ ${CurrencyHelper.formatToCurrency(value)}';

class FinanceSection extends StatelessWidget {
  const FinanceSection({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: FinanceColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class MonthlyOverview extends StatelessWidget {
  const MonthlyOverview({
    super.key,
    required this.gastos,
    required this.onDetails,
  });
  final List<Gasto> gastos;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final open = gastos
        .where((g) => !g.pago)
        .fold<double>(0, (v, g) => v + g.valor);
    final paid = gastos
        .where((g) => g.pago)
        .fold<double>(0, (v, g) => v + g.valor);
    final total = open + paid;
    final fraction = total == 0 ? 0.0 : paid / total;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: FinanceColors.ink,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'A PAGAR NO MÊS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: Color(0xFFB7C8D9),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Color(0xFFB7C8D9),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                money(open),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF5CD4AE),
                backgroundColor: const Color(0xFF36506A),
                semanticsLabel: 'Percentual do valor mensal pago',
                semanticsValue: '${(fraction * 100).round()}%',
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    '${(fraction * 100).round()}% do valor já pago',
                    style: const TextStyle(
                      color: Color(0xFFCAD6E2),
                      fontSize: 12,
                    ),
                  ),
                  InkWell(
                    onTap: onDetails,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver resumo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Total do mês',
                value: money(total),
                icon: Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Já pago',
                value: money(paid),
                icon: Icons.check_circle_outline,
                positive: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.positive = false,
  });
  final String label, value;
  final IconData icon;
  final bool positive;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: FinanceColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: positive ? FinanceColors.green : FinanceColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    super.key,
    required this.gasto,
    required this.now,
    required this.onEdit,
    required this.onPay,
    required this.onDelete,
  });
  final Gasto gasto;
  final DateTime now;
  final VoidCallback onEdit, onPay, onDelete;
  @override
  Widget build(BuildContext context) {
    final overdue = gasto.vencidoEm(now);
    final color = gasto.pago
        ? FinanceColors.green
        : overdue
        ? FinanceColors.red
        : FinanceColors.muted;
    final date = gasto.vencimento;
    final status = gasto.pago
        ? 'Pago'
        : overdue
        ? 'Vencido'
        : 'Em aberto';
    final due = date == null
        ? 'Sem vencimento'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 4, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F3F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                gasto.origem.trim().isEmpty
                    ? '?'
                    : gasto.origem.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gasto.origem,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$status · $due',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money(gasto.valor),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ações de ${gasto.origem}',
              onSelected: (action) {
                if (action == 'pay') {
                  onPay();
                } else if (action == 'edit') {
                  onEdit();
                } else {
                  onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pay',
                  child: Text(
                    gasto.pago ? 'Marcar em aberto' : 'Marcar como pago',
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Editar lançamento'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Excluir lançamento',
                    style: TextStyle(color: FinanceColors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FinanceEmptyState extends StatelessWidget {
  const FinanceEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final String title, message, action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 32,
            color: FinanceColors.muted,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: FinanceColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}
