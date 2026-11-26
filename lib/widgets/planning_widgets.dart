import 'package:flutter/material.dart';

import '../models/gasto.dart';
import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';

/// Committed values of one upcoming month.
class FutureMonth {
  const FutureMonth(this.month, this.fixed, this.installments, this.notes);
  final DateTime month;
  final double fixed, installments;
  final List<String> notes;
  double get total => fixed + installments;
}

/// Installment plan still running (at least one open installment).
class ActivePlan {
  const ActivePlan(this.rows);
  final List<Gasto> rows;
  Gasto get reference => rows.first;
  int get total => reference.parcelaTotal ?? rows.length;
  int get paid => rows.where((g) => g.pago).length;
  Gasto? get next => rows.where((g) => !g.pago).firstOrNull;
  DateTime get end {
    final last = rows.last;
    return last.vencimento ?? DateTime(last.ano, last.mes);
  }
}

/// Everything the Futuro tab shows, computed once per load.
class FuturePlan {
  const FuturePlan({
    required this.months,
    required this.plans,
    required this.fixed,
  });
  final List<FutureMonth> months;
  final List<ActivePlan> plans;
  final List<Gasto> fixed;
  double get fixedTotal => fixed.fold(0, (s, g) => s + g.valor);
  bool get isEmpty =>
      plans.isEmpty && fixed.isEmpty && months.every((m) => m.total == 0);

  /// [current] are this month's expenses, [upcoming] the next months in
  /// order and [groups] every installment of the plans found in them.
  factory FuturePlan.build({
    required List<Gasto> current,
    required List<(DateTime, List<Gasto>)> upcoming,
    required Map<String, List<Gasto>> groups,
  }) {
    final months = [
      for (final (month, rows) in upcoming)
        FutureMonth(
          month,
          rows
              .where((g) => !g.pago && g.recorrenciaId != null)
              .fold(0.0, (s, g) => s + g.valor),
          rows
              .where((g) => !g.pago && g.parcelado)
              .fold(0.0, (s, g) => s + g.valor),
          [
            for (final g in rows.where((g) => !g.pago && g.parcelado))
              '${g.origem} ${g.parcelaNumero}/${g.parcelaTotal}'
                  '${g.parcelaNumero == g.parcelaTotal ? ' (última)' : ''}',
          ],
        ),
    ];
    final plans =
        groups.values
            .where((rows) => rows.isNotEmpty && rows.any((g) => !g.pago))
            .map(
              (rows) => ActivePlan(
                [...rows]..sort(
                  (a, b) =>
                      (a.parcelaNumero ?? 0).compareTo(b.parcelaNumero ?? 0),
                ),
              ),
            )
            .toList()
          ..sort((a, b) => a.end.compareTo(b.end));
    final fixed = <String, Gasto>{};
    for (final rows in [current, for (final m in upcoming) m.$2]) {
      for (final g in rows) {
        if (g.recorrenciaId != null && g.recorrenciaAtiva) {
          fixed.putIfAbsent(g.recorrenciaId!, () => g);
        }
      }
    }
    final fixedList = fixed.values.toList()
      ..sort(
        (a, b) =>
            (a.vencimento?.day ?? 99).compareTo(b.vencimento?.day ?? 99),
      );
    return FuturePlan(months: months, plans: plans, fixed: fixedList);
  }
}

/// "Futuro" tab: next months, running installments and fixed bills.
class FuturoView extends StatefulWidget {
  const FuturoView({
    super.key,
    required this.plan,
    required this.onOpenPlan,
    this.error,
    this.onRetry,
  });
  final FuturePlan? plan;
  final ValueChanged<Gasto> onOpenPlan;
  final String? error;
  final VoidCallback? onRetry;
  @override
  State<FuturoView> createState() => _FuturoViewState();
}

class _FuturoViewState extends State<FuturoView> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Semantics(
          header: true,
          child: const Text('Próximos meses', style: FinanceText.title),
        ),
        const SizedBox(height: 4),
        const Text(
          'O que já está comprometido com contas fixas e parcelas.',
          style: TextStyle(fontSize: 14, color: FinanceColors.muted),
        ),
        const SizedBox(height: 16),
        if (widget.error != null)
          FinanceEmptyState(
            title: 'Não foi possível carregar',
            message: widget.error!,
            action: 'Tentar novamente',
            onAction: widget.onRetry ?? () {},
          )
        else if (plan == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (plan.months.isNotEmpty) _chart(plan),
          const FinanceSection(title: 'Parcelas em andamento'),
          if (plan.plans.isEmpty)
            const _Hint('Nenhuma compra parcelada em aberto.')
          else
            ListCard(
              children: [
                for (final p in plan.plans)
                  _PlanTile(plan: p, onTap: () => widget.onOpenPlan(p.next!)),
              ],
            ),
          FinanceSection(
            title: 'Contas fixas',
            action: plan.fixed.isEmpty
                ? null
                : Text.rich(
                    TextSpan(
                      text: money(plan.fixedTotal),
                      children: const [
                        TextSpan(
                          text: '/mês',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: FinanceColors.muted,
                          ),
                        ),
                      ],
                    ),
                    style: FinanceText.amount.copyWith(fontSize: 14),
                  ),
          ),
          if (plan.fixed.isEmpty)
            const _Hint('Nenhuma conta mensal ativa.')
          else
            ListCard(
              children: [
                for (final g in plan.fixed)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: g.origem,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                if (g.vencimento != null)
                                  TextSpan(
                                    text: ' · dia ${g.vencimento!.day}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: FinanceColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(money(g.valor), style: FinanceText.amount),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _chart(FuturePlan plan) {
    final index = _selected.clamp(0, plan.months.length - 1);
    final current = plan.months[index];
    final max = plan.months.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    const barHeight = 140.0;
    final notes = current.notes.take(2).join(' e ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: FinanceColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${monthNames[current.month.month - 1]} ${current.month.year}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FinanceColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            money(current.total),
            style: const TextStyle(
              fontFamily: FinanceFonts.display,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              height: 1.1,
              fontFeatures: FinanceFonts.tabular,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${money(current.fixed)} fixas + ${money(current.installments)} em parcelas'
            '${notes.isEmpty ? '' : ' · $notes'}',
            style: const TextStyle(fontSize: 13, color: FinanceColors.body),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: barHeight + 26,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < plan.months.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Bar(
                      month: plan.months[i],
                      selected: i == index,
                      scale: max == 0 ? 0 : barHeight / max,
                      onTap: () => setState(() => _selected = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 20),
          const Row(
            children: [
              _Legend(color: FinanceColors.ink, label: 'Contas fixas'),
              SizedBox(width: 16),
              _Legend(color: FinanceColors.olive, label: 'Parcelas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.month,
    required this.selected,
    required this.scale,
    required this.onTap,
  });
  final FutureMonth month;
  final bool selected;
  final double scale;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final fixedH = month.fixed * scale;
    final partsH = month.installments * scale;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${monthNames[month.month.month - 1]} ${month.month.year}: ${money(month.total)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  if (partsH > 0)
                    Container(
                      height: partsH,
                      color: selected
                          ? FinanceColors.olive
                          : FinanceColors.oliveSoft,
                    ),
                  if (partsH > 0 && fixedH > 0) const SizedBox(height: 2),
                  if (fixedH > 0)
                    Container(
                      height: fixedH,
                      color: selected
                          ? FinanceColors.ink
                          : FinanceColors.inkSoft,
                    ),
                  if (partsH <= 0 && fixedH <= 0)
                    Container(height: 3, color: FinanceColors.line),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              monthShort[month.month.month - 1],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? FinanceColors.ink : FinanceColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: FinanceColors.body),
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: FinanceColors.outline),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: FinanceColors.muted),
    ),
  );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.onTap});
  final ActivePlan plan;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final per = plan.next?.valor ?? plan.reference.valor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.reference.origem,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: money(per),
                    children: const [
                      TextSpan(
                        text: '/mês',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: FinanceColors.muted,
                        ),
                      ),
                    ],
                  ),
                  style: FinanceText.amount,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < plan.rows.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: plan.rows[i].pago
                            ? FinanceColors.olive
                            : FinanceColors.chipActive,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${plan.paid} de ${plan.total} pagas',
                  style: const TextStyle(
                    fontSize: 12,
                    color: FinanceColors.muted,
                  ),
                ),
                Text(
                  'termina ${monthYearShort(plan.end)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: FinanceColors.muted,
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

/// Installment plan detail with a one-tap CTA for the next installment.
class InstallmentDetails extends StatefulWidget {
  const InstallmentDetails({
    super.key,
    required this.expenses,
    required this.reference,
    this.onPay,
    this.onReload,
  });
  final List<Gasto> expenses;
  final Gasto reference;

  /// Marks the installment as paid; the page then reloads the plan.
  final Future<void> Function(Gasto)? onPay;
  final Future<List<Gasto>> Function()? onReload;
  @override
  State<InstallmentDetails> createState() => _InstallmentDetailsState();
}

class _InstallmentDetailsState extends State<InstallmentDetails> {
  late List<Gasto> _rows = _sorted(widget.expenses);
  bool _busy = false;

  static List<Gasto> _sorted(List<Gasto> rows) => [...rows]
    ..sort((a, b) => (a.parcelaNumero ?? 0).compareTo(b.parcelaNumero ?? 0));

  Future<void> _payNext(Gasto next) async {
    if (_busy || widget.onPay == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPay!(next);
      final fresh = await widget.onReload?.call();
      if (!mounted) return;
      setState(() {
        _rows = fresh != null
            ? _sorted(fresh)
            : [
                for (final g in _rows) g.id == next.id ? g.copyWith(pago: true) : g,
              ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível registrar a parcela.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.reference;
    final total = ref.parcelaTotal ?? _rows.length;
    final paid = _rows.where((g) => g.pago).length;
    final next = _rows.where((g) => !g.pago).firstOrNull;
    final open = _rows.where((g) => !g.pago).fold<double>(0, (v, g) => v + g.valor);
    final sum = _rows.fold<double>(0, (v, g) => v + g.valor);
    final removed = (total - _rows.length).clamp(0, 120);
    final last = _rows.isEmpty ? null : _rows.last;
    final end = last == null
        ? null
        : (last.vencimento ?? DateTime(last.ano, last.mes));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: FinanceColors.canvas,
            border: Border(top: BorderSide(color: FinanceColors.line)),
          ),
          child: next == null
              ? Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FinanceColors.paidBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Compra quitada',
                    style: TextStyle(
                      color: FinanceColors.paid,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _busy || widget.onPay == null
                      ? null
                      : () => _payNext(next),
                  child: Text(
                    'Marcar parcela ${next.parcelaNumero} como paga',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              CategoryTile(category: ref.categoria, size: 52, outlined: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ref.origem, style: FinanceText.title),
                    const SizedBox(height: 2),
                    Text(
                      '${ref.categoria} · $total× de ${money(next?.valor ?? ref.valor)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: FinanceColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: FinanceColors.ink,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Falta pagar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: FinanceColors.onInkMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyText(
                              open,
                              size: 36,
                              color: Colors.white,
                              secondary: FinanceColors.onInkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'de ${money(sum)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: FinanceColors.onInkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: '$paid de $total parcelas pagas',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (var i = 0; i < _rows.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: _rows[i].pago
                                  ? FinanceColors.lime
                                  : _rows[i].id == next?.id
                                  ? FinanceColors.inkNext
                                  : FinanceColors.inkTrack,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$paid de $total',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' pagas'),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: FinanceColors.onInkMuted,
                      ),
                    ),
                    if (end != null)
                      Text.rich(
                        TextSpan(
                          text: 'Termina em ',
                          children: [
                            TextSpan(
                              text: monthYearShort(end),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: FinanceColors.onInkMuted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (removed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '$removed parcelas foram excluídas. Os valores consideram apenas as parcelas cadastradas.',
                style: FinanceText.caption,
              ),
            ),
          const FinanceSection(title: 'Parcelas'),
          ListCard(
            children: [
              for (final g in _rows) _InstallmentRow(g: g, next: g.id == next?.id),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({required this.g, required this.next});
  final Gasto g;
  final bool next;
  @override
  Widget build(BuildContext context) {
    final due = g.vencimento;
    final dueText = due == null
        ? ''
        : '${twoDigits(due.day)}/${twoDigits(due.month)}';
    final sub = g.pago
        ? 'Paga${dueText.isEmpty ? '' : ' · venceu $dueText'}'
        : next
        ? 'Próxima${dueText.isEmpty ? '' : ' · vence $dueText'}'
        : (dueText.isEmpty ? 'Em aberto' : 'Vence $dueText');
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: next
          ? const BoxDecoration(
              color: FinanceColors.nextRow,
              border: Border(
                left: BorderSide(color: FinanceColors.ink, width: 3),
              ),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: g.pago
                  ? FinanceColors.paid
                  : next
                  ? FinanceColors.ink
                  : FinanceColors.chip,
            ),
            child: Text(
              '${g.parcelaNumero}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: g.pago
                    ? Colors.white
                    : next
                    ? FinanceColors.lime
                    : FinanceColors.body,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${monthNames[g.mes - 1]} ${g.ano}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: g.pago
                        ? FinanceColors.paid
                        : next
                        ? FinanceColors.ink
                        : FinanceColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            money(g.valor),
            style: FinanceText.amount.copyWith(
              color: g.pago ? FinanceColors.muted : FinanceColors.ink,
              decoration: g.pago ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
