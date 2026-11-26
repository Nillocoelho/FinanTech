import 'package:flutter/material.dart';

import '../models/expense_category.dart';
import '../models/gasto.dart';
import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';
import '../utils/currency_helper.dart';
import '../utils/installment_helper.dart';

class ExpenseDraft {
  const ExpenseDraft({
    required this.name,
    required this.amount,
    required this.due,
    required this.installments,
    this.category = ExpenseCategory.uncategorized,
    this.recurring = false,
  });
  final String name;
  final double amount;
  final DateTime due;
  final int installments;
  final String category;
  final bool recurring;
}

/// How the bill is charged. The three options are mutually exclusive.
enum ChargeType { unica, parcelada, mensal }

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.period,
    required this.origins,
    this.expense,
    this.seriesEdit = false,
    this.now,
  });
  final DateTime period;
  final List<String> origins;
  final Gasto? expense;
  final bool seriesEdit;
  final DateTime? now;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  static const _minInstallments = 2, _maxInstallments = 120;
  final _form = GlobalKey<FormState>();
  final _amountFocus = FocusNode();
  late final TextEditingController _name, _amount;
  late DateTime _base;
  DateTime? _due;
  DateTime? _custom;
  ChargeType _type = ChargeType.unica;
  int _count = 10;
  String _category = ExpenseCategory.uncategorized;

  bool get _isNew => widget.expense == null;

  @override
  void initState() {
    super.initState();
    final now = dateOnly(widget.now ?? DateTime.now());
    final p = widget.period;
    // Quick dates follow the month being edited; "Hoje" only in the current month.
    _base = p.year == now.year && p.month == now.month
        ? now
        : DateTime(
            p.year,
            p.month,
            now.day.clamp(1, DateTime(p.year, p.month + 1, 0).day),
          );
    _name = TextEditingController(text: widget.expense?.origem);
    _amount = TextEditingController(
      text: widget.expense == null
          ? ''
          : CurrencyHelper.formatToCurrency(widget.expense!.valor),
    );
    _amountFocus.addListener(() => setState(() {}));
    _due = widget.expense?.vencimento ?? (_isNew ? _base : null);
    if (_due != null && !_quick.contains(dateOnly(_due!))) {
      _custom = dateOnly(_due!);
    }
    _category = widget.expense?.categoria ?? ExpenseCategory.uncategorized;
  }

  List<DateTime> get _quick => [
    _base,
    _base.add(const Duration(days: 1)),
  ];

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  double get _value => CurrencyHelper.parseFromCurrency(_amount.text);

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final result = await showDatePicker(
      context: context,
      initialDate: _due ?? _base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Vencimento da conta',
    );
    if (result != null && mounted) {
      setState(() {
        _due = dateOnly(result);
        _custom = _quick.contains(_due) ? _custom : _due;
      });
    }
  }

  Future<void> _typeCount() async {
    final controller = TextEditingController(text: '$_count');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quantidade de parcelas'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(helperText: 'De 2 a 120'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      setState(
        () => _count = value.clamp(_minInstallments, _maxInstallments),
      );
    }
  }

  String? _installmentError(double amount) {
    if (_type != ChargeType.parcelada) return null;
    if ((amount * 100).round() < _count) {
      return 'Cada parcela deve ter ao menos R\$ 0,01.';
    }
    return null;
  }

  void _submit() {
    final amount = _value;
    _tried = true;
    final valid = _form.currentState!.validate();
    if (!valid || _due == null || _installmentError(amount) != null) {
      setState(() {});
      return;
    }
    Navigator.pop(
      context,
      ExpenseDraft(
        name: _name.text.trim(),
        category: _category,
        recurring: _isNew && _type == ChargeType.mensal,
        amount: amount,
        due: _due!,
        installments: _isNew && _type == ChargeType.parcelada ? _count : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = _value;
    final parts = _type == ChargeType.parcelada && amount > 0
        ? InstallmentHelper.splitAmount(amount, _count)
        : const <double>[];
    final due = _due ?? _base;
    final lastDue = DateTime(due.year, due.month + _count - 1);
    final (cta, ctaValue) = !_isNew
        ? ('Salvar alterações', null)
        : switch (_type) {
            ChargeType.parcelada => (
              'Adicionar $_count parcelas',
              parts.isEmpty ? null : '· $_count× ${money(parts.first)}',
            ),
            ChargeType.mensal => (
              'Adicionar conta mensal',
              amount > 0 ? '· ${money(amount)}' : null,
            ),
            ChargeType.unica => (
              'Adicionar conta',
              amount > 0 ? '· ${money(amount)}' : null,
            ),
          };
    final installmentError = _installmentError(amount);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      _isNew ? 'Novo lançamento' : 'Editar lançamento',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _amountField(),
                    if (widget.expense?.parcelado == true)
                      _note(
                        'Parcela ${widget.expense!.parcelaNumero} de ${widget.expense!.parcelaTotal}. A edição afeta somente esta parcela.',
                      ),
                    if (widget.expense?.recorrenciaId != null)
                      _note(
                        widget.seriesEdit
                            ? 'Aplica a este e aos próximos lançamentos em aberto. Pagamentos já registrados serão mantidos.'
                            : 'A edição afeta somente este mês.',
                      ),
                    const SizedBox(height: 18),
                    const Text('Nome ou instituição', style: FinanceText.label),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ex.: Aluguel, Nubank, Internet',
                        suffixIcon: widget.origins.isEmpty
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Usar um nome existente',
                                icon: const Icon(Icons.expand_more),
                                onSelected: (value) => _name.text = value,
                                itemBuilder: (_) => widget.origins
                                    .map(
                                      (o) => PopupMenuItem(
                                        value: o,
                                        child: Text(o),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Informe o nome da conta.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    const Text('Categoria', style: FinanceText.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in {...ExpenseCategory.values, _category})
                          _ChoicePill(
                            label: c,
                            icon: categoryIcon(c),
                            selected: c == _category,
                            onTap: () => setState(() => _category = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('Vencimento', style: FinanceText.label),
                    const SizedBox(height: 8),
                    _dueChips(),
                    if (_due == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          'Selecione o vencimento.',
                          style: TextStyle(
                            color: FinanceColors.late,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_isNew) ...[
                      const SizedBox(height: 18),
                      const Text('Como é cobrada', style: FinanceText.label),
                      const SizedBox(height: 10),
                      _typeSelector(),
                      const SizedBox(height: 10),
                      if (_type == ChargeType.parcelada)
                        _installmentsCard(parts, due, lastDue, installmentError)
                      else
                        _InfoCard(
                          child: Text.rich(
                            _type == ChargeType.mensal
                                ? TextSpan(
                                    text: 'Repete todo ',
                                    children: [
                                      TextSpan(
                                        text: 'dia ${due.day}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: FinanceColors.ink,
                                        ),
                                      ),
                                      const TextSpan(
                                        text:
                                            ', com o mesmo valor, até você encerrar. Ideal para aluguel, assinaturas e contas fixas.',
                                      ),
                                    ],
                                  )
                                : TextSpan(
                                    text: 'Uma cobrança só, em ',
                                    children: [
                                      TextSpan(
                                        text: shortDate(due, reference: _base),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: FinanceColors.ink,
                                        ),
                                      ),
                                      const TextSpan(
                                        text:
                                            '. Contas avulsas com o mesmo nome no mês têm os valores somados.',
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: FinanceColors.canvas,
                border: Border(top: BorderSide(color: FinanceColors.line)),
              ),
              child: SafeArea(
                top: false,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _submit,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          cta,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      if (ctaValue != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          ctaValue,
                          style: const TextStyle(
                            fontSize: 16,
                            color: FinanceColors.lime,
                            fontFeatures: FinanceFonts.tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(text, textAlign: TextAlign.center, style: FinanceText.caption),
  );

  /// Big amount with smaller cents; a transparent field captures typing.
  Widget _amountField() {
    final amount = _value;
    final focused = _amountFocus.hasFocus;
    return Column(
      children: [
        Text(
          widget.expense?.parcelado == true ? 'Valor desta parcela' : 'Valor total',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FinanceColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MoneyText(
                          amount,
                          size: 54,
                          color: _amount.text.isEmpty
                              ? FinanceColors.outline
                              : FinanceColors.ink,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: focused ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: 2,
                        height: 46,
                        margin: const EdgeInsets.only(left: 4),
                        color: FinanceColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: TextFormField(
                controller: _amount,
                focusNode: _amountFocus,
                showCursor: false,
                enableInteractiveSelection: false,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  errorStyle: TextStyle(height: 0, fontSize: 0),
                  contentPadding: EdgeInsets.zero,
                  semanticCounterText: '',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [CurrencyInputFormatter()],
                onChanged: (_) => setState(() {}),
                validator: (v) => CurrencyHelper.parseFromCurrency(v ?? '') <= 0
                    ? 'Informe um valor maior que zero.'
                    : null,
              ),
            ),
          ],
        ),
        if (_tried && amount <= 0)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Informe um valor maior que zero.',
              style: TextStyle(color: FinanceColors.late, fontSize: 12),
            ),
          ),
      ],
    );
  }

  bool _tried = false;

  Widget _dueChips() {
    final options = <(String, String, DateTime?)>[
      for (final d in _quick)
        (
          d == dateOnly(widget.now ?? DateTime.now())
              ? 'Hoje'
              : d == dateOnly(widget.now ?? DateTime.now()).add(const Duration(days: 1))
              ? 'Amanhã'
              : weekdayShort[d.weekday - 1],
          shortDate(d),
          d,
        ),
      if (_custom != null)
        (weekdayShort[_custom!.weekday - 1], shortDate(_custom!), _custom),
      ('Outra', 'data', null),
    ];
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _DueChip(
              top: options[i].$1,
              bottom: options[i].$2,
              selected: options[i].$3 != null && options[i].$3 == _due,
              onTap: options[i].$3 == null
                  ? _pickDate
                  : () => setState(() => _due = options[i].$3),
            ),
          ),
        ],
      ],
    );
  }

  Widget _typeSelector() => Semantics(
    label: 'Tipo de cobrança',
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FinanceColors.track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final t in ChargeType.values)
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: t == _type,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t == _type ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: t == _type
                          ? const [
                              BoxShadow(
                                color: Color(0x2614161A),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      switch (t) {
                        ChargeType.unica => 'Única',
                        ChargeType.parcelada => 'Parcelada',
                        ChargeType.mensal => 'Mensal',
                      },
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t == _type
                            ? FinanceColors.ink
                            : FinanceColors.body,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _installmentsCard(
    List<double> parts,
    DateTime due,
    DateTime lastDue,
    String? error,
  ) => _InfoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Parcelas',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: FinanceColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Menos parcelas',
                    onPressed: _count > _minInstallments
                        ? () => setState(() => _count--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Semantics(
                    button: true,
                    label: '$_count parcelas. Toque para digitar',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: _typeCount,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Text(
                            '$_count×',
                            style: const TextStyle(
                              fontFamily: FinanceFonts.display,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              fontFeatures: FinanceFonts.tabular,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mais parcelas',
                    onPressed: _count < _maxInstallments
                        ? () => setState(() => _count++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            _Stat(
              label: 'Por mês',
              value: parts.isEmpty ? '—' : money(parts.first),
            ),
            _Stat(label: 'Primeira', value: shortDate(due, reference: _base)),
            _Stat(label: 'Última', value: monthYearShort(lastDue)),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              error,
              style: const TextStyle(color: FinanceColors.late, fontSize: 12),
            ),
          ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: FinanceColors.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFeatures: FinanceFonts.tabular,
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: FinanceColors.line),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 14,
        height: 1.5,
        color: FinanceColors.body,
      ),
      child: child,
    ),
  );
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: selected ? FinanceColors.ink : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? FinanceColors.ink : FinanceColors.line,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : FinanceColors.ink,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : FinanceColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.top,
    required this.bottom,
    required this.selected,
    required this.onTap,
  });
  final String top, bottom;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : FinanceColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: '$top $bottom',
      excludeSemantics: true,
      child: Material(
        color: selected ? FinanceColors.ink : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? FinanceColors.ink : FinanceColors.line,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  top,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bottom,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
