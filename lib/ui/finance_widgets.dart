import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/gasto.dart';
import '../utils/currency_helper.dart';
import 'finance_theme.dart';

String money(double value) => 'R\$ ${CurrencyHelper.formatToCurrency(value)}';

const monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];
const monthShort = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];
const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "18 nov", or "18 nov 2027" outside the reference year.
String shortDate(DateTime d, {DateTime? reference}) =>
    '${d.day} ${monthShort[d.month - 1]}'
    '${reference != null && reference.year != d.year ? ' ${d.year}' : ''}';

/// "jan/2027"
String monthYearShort(DateTime d) => '${monthShort[d.month - 1]}/${d.year}';

String twoDigits(int v) => v.toString().padLeft(2, '0');

int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inHours ~/ 24;

enum DueTone { late, soon, plain, paid }

/// Relative status of an expense, the first thing the user reads.
({String label, DueTone tone}) dueStatus(Gasto g, DateTime now) {
  if (g.pago) return (label: 'Paga', tone: DueTone.paid);
  final due = g.vencimento;
  if (due == null) return (label: 'Sem vencimento', tone: DueTone.plain);
  final diff = daysBetween(now, due);
  if (diff < 0) {
    return (
      label: 'Venceu há ${-diff} ${diff == -1 ? 'dia' : 'dias'}',
      tone: DueTone.late,
    );
  }
  if (diff == 0) return (label: 'Vence hoje', tone: DueTone.soon);
  if (diff <= 3) {
    return (label: 'Em $diff ${diff == 1 ? 'dia' : 'dias'}', tone: DueTone.soon);
  }
  return (label: shortDate(due, reference: now), tone: DueTone.plain);
}

Color dueColor(DueTone tone) => switch (tone) {
  DueTone.late => FinanceColors.late,
  DueTone.soon => FinanceColors.soon,
  DueTone.paid => FinanceColors.paid,
  DueTone.plain => FinanceColors.muted,
};

/// "Mensal", "1/10" or null.
String? planTag(Gasto g) => g.parcelado
    ? '${g.parcelaNumero}/${g.parcelaTotal}'
    : g.recorrenciaId != null
    ? (g.recorrenciaAtiva ? 'Mensal' : 'Encerrada')
    : null;

IconData categoryIcon(String category) => switch (category) {
  'Moradia' => Icons.home_outlined,
  'Alimentação' => Icons.restaurant_outlined,
  'Transporte' => Icons.directions_car_outlined,
  'Saúde' => Icons.favorite_border,
  'Educação' => Icons.school_outlined,
  'Lazer' => Icons.local_activity_outlined,
  'Assinaturas' => Icons.autorenew,
  'Compras' => Icons.shopping_bag_outlined,
  'Outros' => Icons.category_outlined,
  ExpenseCategory.uncategorized => Icons.receipt_long_outlined,
  _ => Icons.label_outline,
};

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    this.size = 40,
    this.outlined = false,
  });
  final String category;
  final double size;
  final bool outlined;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: outlined ? Colors.white : FinanceColors.chip,
      borderRadius: BorderRadius.circular(size * 0.3),
      border: outlined ? Border.all(color: FinanceColors.line) : null,
    ),
    child: Icon(
      categoryIcon(category),
      size: size / 2,
      color: outlined ? FinanceColors.ink : FinanceColors.body,
    ),
  );
}

/// Amount with smaller cents and tabular figures: "R$ 2.736,80".
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.size = 52,
    this.color = FinanceColors.ink,
    this.secondary = FinanceColors.muted,
  });
  final double value, size;
  final Color color, secondary;
  @override
  Widget build(BuildContext context) {
    final parts = CurrencyHelper.formatToCurrency(value).split(',');
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: FinanceFonts.display,
          fontWeight: FontWeight.w700,
          letterSpacing: -size * 0.03,
          fontFeatures: FinanceFonts.tabular,
          color: color,
          height: 1,
        ),
        children: [
          TextSpan(
            text: 'R\$ ',
            style: TextStyle(fontSize: size * 0.42, color: secondary),
          ),
          TextSpan(
            text: parts.first,
            style: TextStyle(fontSize: size),
          ),
          TextSpan(
            text: ',${parts.last}',
            style: TextStyle(fontSize: size * 0.5, color: secondary),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
    );
  }
}

/// Horizontal bar split in colored parts (fractions of the whole).
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.parts,
    this.height = 8,
    this.track = FinanceColors.inkTrack,
    this.gap = 2,
    this.semanticsLabel,
  });
  final List<(double, Color)> parts;
  final double height, gap;
  final Color track;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.$1 > 0.0005).toList();
    final used = visible.fold<double>(0, (s, p) => s + p.$1).clamp(0.0, 1.0);
    final children = <Widget>[];
    for (final p in visible) {
      if (children.isNotEmpty) children.add(SizedBox(width: gap));
      children.add(
        Expanded(
          flex: (p.$1 * 10000).round().clamp(1, 10000),
          child: ColoredBox(color: p.$2),
        ),
      );
    }
    if (used < 0.9995) {
      children.add(
        Expanded(
          flex: ((1 - used) * 10000).round().clamp(1, 10000),
          child: const SizedBox(),
        ),
      );
    }
    return Semantics(
      label: semanticsLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: track,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class FinanceSection extends StatelessWidget {
  const FinanceSection({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.count,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (count != null)
                        TextSpan(
                          text: '  $count',
                          style: const TextStyle(
                            fontFamily: FinanceFonts.ui,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: FinanceColors.muted,
                          ),
                        ),
                    ],
                  ),
                  style: FinanceText.section,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: FinanceText.caption),
              ],
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// White rounded card that stacks rows separated by hairlines.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: FinanceColors.line),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Callbacks offered for an expense (menu, long press and quick toggle).
class ExpenseActions {
  const ExpenseActions({
    required this.onEdit,
    required this.onPay,
    required this.onDelete,
    this.onInstallments,
    this.onStopRecurring,
  });
  final VoidCallback onEdit, onPay, onDelete;
  final VoidCallback? onInstallments, onStopRecurring;
}

List<(String, String, IconData)> _actionItems(Gasto g, ExpenseActions a) => [
  (
    'pay',
    g.pago ? 'Marcar em aberto' : 'Marcar como pago',
    g.pago ? Icons.undo : Icons.check_circle_outline,
  ),
  ('edit', 'Editar lançamento', Icons.edit_outlined),
  if (a.onInstallments != null)
    ('installments', 'Ver parcelamento', Icons.view_week_outlined),
  if (a.onStopRecurring != null)
    ('stop', 'Encerrar repetição', Icons.event_busy_outlined),
  ('delete', 'Excluir lançamento', Icons.delete_outline),
];

void _runAction(String id, ExpenseActions a) => switch (id) {
  'pay' => a.onPay(),
  'edit' => a.onEdit(),
  'installments' => a.onInstallments?.call(),
  'stop' => a.onStopRecurring?.call(),
  _ => a.onDelete(),
};

Future<void> showExpenseActions(
  BuildContext context,
  Gasto g,
  ExpenseActions actions,
) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '${g.origem} · ${money(g.valor)}',
              style: FinanceText.section,
            ),
          ),
          for (final item in _actionItems(g, actions))
            ListTile(
              leading: Icon(
                item.$3,
                color: item.$1 == 'delete' ? FinanceColors.late : null,
              ),
              title: Text(
                item.$2,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: item.$1 == 'delete' ? FinanceColors.late : null,
                ),
              ),
              onTap: () => Navigator.pop(ctx, item.$1),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (id != null) _runAction(id, actions);
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.gasto, required this.actions});
  final Gasto gasto;
  final ExpenseActions actions;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Ações de ${gasto.origem}',
    icon: const Icon(Icons.more_vert, color: FinanceColors.muted, size: 20),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(minimumSize: const Size(40, 44)),
    onSelected: (id) => _runAction(id, actions),
    itemBuilder: (_) => [
      for (final item in _actionItems(gasto, actions))
        PopupMenuItem(
          value: item.$1,
          child: Text(
            item.$2,
            style: item.$1 == 'delete'
                ? const TextStyle(color: FinanceColors.late)
                : null,
          ),
        ),
    ],
  );
}

/// 44px hit area with the 24px circle that toggles the paid state.
class PayToggle extends StatelessWidget {
  const PayToggle({
    super.key,
    required this.paid,
    required this.name,
    required this.onTap,
  });
  final bool paid;
  final String name;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    checked: paid,
    label: paid ? 'Marcar $name como não paga' : 'Marcar $name como paga',
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: paid ? FinanceColors.paid : Colors.transparent,
              border: paid
                  ? null
                  : Border.all(color: FinanceColors.toggle, width: 2),
            ),
            child: paid
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : null,
          ),
        ),
      ),
    ),
  );
}

/// Home row: one tap on the circle pays the bill.
class PayableRow extends StatelessWidget {
  const PayableRow({
    super.key,
    required this.gasto,
    required this.now,
    required this.actions,
  });
  final Gasto gasto;
  final DateTime now;
  final ExpenseActions actions;
  @override
  Widget build(BuildContext context) {
    final status = dueStatus(gasto, now);
    final paid = gasto.pago;
    final meta = [
      gasto.categoria,
      if (gasto.parcelado)
        'Parcela ${gasto.parcelaNumero} de ${gasto.parcelaTotal}'
      else if (gasto.recorrenciaId != null && gasto.recorrenciaAtiva)
        'Mensal',
    ].join(' · ');
    return InkWell(
      onTap: actions.onEdit,
      onLongPress: () => showExpenseActions(context, gasto, actions),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
          child: Row(
            children: [
              PayToggle(paid: paid, name: gasto.origem, onTap: actions.onPay),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gasto.origem,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: paid ? FinanceColors.muted : FinanceColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FinanceText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(gasto.valor),
                    style: FinanceText.amount.copyWith(
                      color: paid ? FinanceColors.muted : FinanceColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: dueColor(status.tone),
                    ),
                  ),
                ],
              ),
              _ActionsMenu(gasto: gasto, actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contas row: category tile, plan tag and relative due label.
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    super.key,
    required this.gasto,
    required this.now,
    required this.actions,
  });
  final Gasto gasto;
  final DateTime now;
  final ExpenseActions actions;
  @override
  Widget build(BuildContext context) {
    final status = dueStatus(gasto, now);
    final tag = planTag(gasto);
    return InkWell(
      onTap: actions.onEdit,
      onLongPress: () => showExpenseActions(context, gasto, actions),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
          child: Row(
            children: [
              CategoryTile(category: gasto.categoria),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gasto.origem,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            gasto.categoria,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: FinanceColors.muted,
                            ),
                          ),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: FinanceColors.chip,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: FinanceColors.body,
                                fontFeatures: FinanceFonts.tabular,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(gasto.valor),
                    style: FinanceText.amount.copyWith(
                      color: gasto.pago
                          ? FinanceColors.muted
                          : FinanceColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: dueColor(status.tone),
                    ),
                  ),
                ],
              ),
              _ActionsMenu(gasto: gasto, actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable pill with an optional counter (lime when active).
class CountChip extends StatelessWidget {
  const CountChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: count == null ? label : '$label, $count',
    excludeSemantics: true,
    child: Material(
      color: selected ? FinanceColors.ink : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? FinanceColors.ink : FinanceColors.line,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : FinanceColors.ink,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? FinanceColors.lime : FinanceColors.chip,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: FinanceFonts.tabular,
                      color: selected ? FinanceColors.ink : FinanceColors.body,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Compact month switcher used in Contas ("‹ nov 2026 ›").
class MonthStepper extends StatelessWidget {
  const MonthStepper({
    super.key,
    required this.period,
    required this.onChanged,
    this.onPick,
  });
  final DateTime period;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onPick;
  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: FinanceColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MonthArrow(period: period, forward: false, onChanged: onChanged),
        InkWell(
          onTap: onPick,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            child: Text(
              '${monthShort[period.month - 1]} ${period.year}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        MonthArrow(period: period, forward: true, onChanged: onChanged),
      ],
    ),
  );
}

/// Previous/next month button, disabled outside 2000..2100.
class MonthArrow extends StatelessWidget {
  const MonthArrow({
    super.key,
    required this.period,
    required this.forward,
    required this.onChanged,
  });
  final DateTime period;
  final bool forward;
  final ValueChanged<DateTime> onChanged;
  static final first = DateTime(2000, 1);
  static final last = DateTime(2100, 12);
  @override
  Widget build(BuildContext context) {
    final target = DateTime(period.year, period.month + (forward ? 1 : -1));
    final enabled = !target.isBefore(first) && !target.isAfter(last);
    return IconButton(
      tooltip: forward ? 'Próximo mês' : 'Mês anterior',
      onPressed: enabled ? () => onChanged(target) : null,
      style: IconButton.styleFrom(minimumSize: const Size(40, 44)),
      icon: Icon(forward ? Icons.chevron_right : Icons.chevron_left, size: 22),
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
    this.leading,
  });
  final String title, message, action;
  final VoidCallback onAction;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: FinanceColors.outline),
    ),
    child: Column(
      children: [
        leading ??
            const Icon(
              Icons.receipt_long_outlined,
              size: 30,
              color: FinanceColors.muted,
            ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: FinanceText.section.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: FinanceColors.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}
