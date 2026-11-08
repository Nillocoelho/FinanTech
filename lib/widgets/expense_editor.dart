import 'package:flutter/material.dart';

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
  });
  final String name;
  final double amount;
  final DateTime due;
  final int installments;
}

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.period,
    required this.origins,
    this.expense,
  });
  final DateTime period;
  final List<String> origins;
  final Gasto? expense;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _amount;
  final _count = TextEditingController(text: '2');
  DateTime? _due;
  bool _installments = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.expense?.origem);
    _amount = TextEditingController(
      text: widget.expense == null
          ? ''
          : CurrencyHelper.formatToCurrency(widget.expense!.valor),
    );
    _due = widget.expense?.vencimento;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final suggested =
        _due ??
        DateTime(
          widget.period.year,
          widget.period.month,
          now.day.clamp(
            1,
            DateTime(widget.period.year, widget.period.month + 1, 0).day,
          ),
        );
    final result = await showDatePicker(
      context: context,
      initialDate: suggested,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Vencimento da conta',
    );
    if (result != null && mounted) {
      setState(() => _due = result);
      field.didChange(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = CurrencyHelper.parseFromCurrency(_amount.text);
    final count = int.tryParse(_count.text) ?? 0;
    final preview = _installments && count >= 2 && count <= 120 && amount > 0
        ? InstallmentHelper.splitAmount(amount, count)
        : <double>[];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.expense == null
                    ? 'Novo lançamento'
                    : 'Editar lançamento',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Organize uma conta e acompanhe o vencimento.',
                style: TextStyle(color: FinanceColors.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _amount,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: 'Valor total',
                  prefixText: 'R\$ ',
                ),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nome ou instituição',
                  hintText: 'Ex.: Aluguel, Nubank, Internet',
                  suffixIcon: widget.origins.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Usar um nome existente',
                          icon: const Icon(Icons.expand_more),
                          onSelected: (value) => _name.text = value,
                          itemBuilder: (_) => widget.origins
                              .map(
                                (o) => PopupMenuItem(value: o, child: Text(o)),
                              )
                              .toList(),
                        ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Informe o nome da conta.'
                    : null,
              ),
              const SizedBox(height: 16),
              FormField<DateTime>(
                initialValue: _due,
                validator: (_) =>
                    _due == null ? 'Selecione o vencimento.' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: ListTile(
                        onTap: () => _pickDate(field),
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text(
                          'Vencimento',
                          style: TextStyle(
                            fontSize: 13,
                            color: FinanceColors.muted,
                          ),
                        ),
                        subtitle: Text(
                          _due == null
                              ? 'Selecione uma data'
                              : '${_due!.day.toString().padLeft(2, '0')}/${_due!.month.toString().padLeft(2, '0')}/${_due!.year}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                    if (field.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 12),
                        child: Text(
                          field.errorText!,
                          style: const TextStyle(
                            color: FinanceColors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.expense == null) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Dividir em parcelas',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Uma parcela por mês',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _installments,
                  onChanged: (value) => setState(() => _installments = value),
                ),
                if (_installments) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _count,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade de parcelas',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse(v ?? '') ?? 0;
                      return n < 2 || n > 120
                          ? 'Use de 2 a 120 parcelas.'
                          : n > (amount * 100).round()
                          ? 'Cada parcela deve ter ao menos R\$ 0,01.'
                          : null;
                    },
                  ),
                  if (preview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '$count parcelas a partir de ${money(preview.last)}. Total de ${money(amount)}.',
                        style: const TextStyle(
                          color: FinanceColors.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 20),
              if (widget.expense == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Contas com o mesmo nome no mesmo mês terão os valores somados.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: FinanceColors.muted,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(
                      context,
                      ExpenseDraft(
                        name: _name.text.trim(),
                        amount: CurrencyHelper.parseFromCurrency(_amount.text),
                        due: _due!,
                        installments: _installments
                            ? int.parse(_count.text)
                            : 1,
                      ),
                    );
                  }
                },
                child: Text(
                  widget.expense == null
                      ? 'Adicionar lançamento'
                      : 'Salvar alterações',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
