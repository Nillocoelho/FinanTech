import 'dart:async';

import 'package:flutter/material.dart';

import '../data/gastos_repository.dart';
import '../data/preferences_service.dart';
import '../models/gasto.dart';
import '../ui/brand.dart';
import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';
import '../widgets/expense_editor.dart';
import '../widgets/planning_widgets.dart';
import 'configuracoes_page.dart';

enum FiltroStatus { todos, abertos, vencidos, pagos }

int _compareDue(Gasto a, Gasto b) => (a.vencimento ?? DateTime(9999))
    .compareTo(b.vencimento ?? DateTime(9999));

/// Values of the Início tab, computed once per data change.
class HomeSummary {
  HomeSummary(List<Gasto> expenses, DateTime now)
    : open = expenses.where((g) => !g.pago).toList()..sort(_compareDue),
      paidRows = expenses.where((g) => g.pago).toList()..sort(_compareDue),
      late = expenses.where((g) => g.vencidoEm(now)).toList()..sort(_compareDue) {
    total = expenses.fold(0, (s, g) => s + g.valor);
    paid = paidRows.fold(0, (s, g) => s + g.valor);
    lateTotal = late.fold(0, (s, g) => s + g.valor);
    final byCategory = <String, double>{};
    for (final g in expenses) {
      byCategory.update(g.categoria, (v) => v + g.valor, ifAbsent: () => g.valor);
    }
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    categories = sorted.length <= 5
        ? sorted.map((e) => (e.key, e.value)).toList()
        : [
            ...sorted.take(4).map((e) => (e.key, e.value)),
            ('Outras', sorted.skip(4).fold(0.0, (s, e) => s + e.value)),
          ];
  }
  final List<Gasto> open, paidRows, late;
  late final double total, paid, lateTotal;
  late final List<(String, double)> categories;
  double get remaining => total - paid;
}

class GastosPage extends StatefulWidget {
  const GastosPage({super.key, this.repository, this.now});
  final GastosRepository? repository;
  final DateTime Function()? now;
  @override
  State<GastosPage> createState() => _GastosPageState();
}

class _GastosPageState extends State<GastosPage> {
  late final GastosRepository _repository;
  final _preferences = PreferencesService();
  late DateTime _period;
  List<Gasto> _expenses = [];
  HomeSummary? _summary;
  List<String> _origins = [];
  FuturePlan? _plan;
  String? _planError;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _tab = 0;
  int _loadGeneration = 0;
  int _planGeneration = 0;
  FiltroStatus _contasFilter = FiltroStatus.todos;
  int _contasReset = 0;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? GastosRepository();
    _period = DateTime(_now.year, _now.month);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final saved = await _preferences.getMesAnoSelecionado();
      if (!mounted) return;
      _period = DateTime(saved.ano, saved.mes);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir seus lançamentos.';
        });
      }
    }
  }

  void _setExpenses(List<Gasto> expenses) {
    _expenses = expenses;
    _summary = HomeSummary(expenses, _now);
  }

  /// [quiet] keeps the current content on screen while refreshing.
  Future<void> _load({bool quiet = false}) async {
    final generation = ++_loadGeneration;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final period = _period;
      await _repository.prepararMes(period.month, period.year, now: _now);
      final result = await Future.wait([
        _repository.getGastosDoMes(period.month, period.year),
        _repository.getOrigensDistintas(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _setExpenses(result[0] as List<Gasto>);
        _origins = result[1] as List<String>;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error =
            'Não foi possível carregar este mês. Seus dados não foram alterados.';
      });
    }
    unawaited(_loadPlan());
  }

  /// Futuro tab: the six months after today, plus running plans.
  Future<void> _loadPlan() async {
    final generation = ++_planGeneration;
    try {
      final now = _now;
      final current = await _repository.getGastosDoMes(now.month, now.year);
      final months = [
        for (var i = 1; i <= 6; i++) DateTime(now.year, now.month + i),
      ];
      final upcoming = await Future.wait(
        months.map((m) => _repository.getGastosDoMes(m.month, m.year)),
      );
      final groups = <String>{
        for (final rows in [current, ...upcoming])
          for (final g in rows)
            if (g.parcelaGrupo != null) g.parcelaGrupo!,
      };
      final plans = await Future.wait(groups.map(_repository.getParcelas));
      if (!mounted || generation != _planGeneration) return;
      setState(() {
        _planError = null;
        _plan = FuturePlan.build(
          current: current,
          upcoming: [for (var i = 0; i < 6; i++) (months[i], upcoming[i])],
          groups: {
            for (var i = 0; i < groups.length; i++)
              groups.elementAt(i): plans[i],
          },
        );
      });
    } catch (_) {
      if (!mounted || generation != _planGeneration) return;
      setState(
        () => _planError = 'Não foi possível calcular os próximos meses.',
      );
    }
  }

  Future<void> _changePeriod(DateTime period) async {
    if (period.isBefore(MonthArrow.first) || period.isAfter(MonthArrow.last)) {
      return;
    }
    setState(() => _period = period);
    await _load();
    try {
      await _preferences.salvarMesAnoSelecionado(period.month, period.year);
    } catch (_) {
      if (mounted) _message('O período não pôde ser salvo nas preferências.');
    }
  }

  void _message(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  ExpenseActions _actionsFor(Gasto g) => ExpenseActions(
    onEdit: () => _edit(g),
    onPay: () => _setPaid([g], !g.pago),
    onDelete: () => _delete(g),
    onInstallments: g.parcelado ? () => _installments(g) : null,
    onStopRecurring: g.recorrenciaId != null && g.recorrenciaAtiva
        ? () => _stopRecurring(g)
        : null,
  );

  Future<void> _edit([Gasto? expense]) async {
    if (_saving) return;
    var editSeries = false;
    if (expense?.recorrenciaId != null && expense!.recorrenciaAtiva) {
      final scope = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Editar conta recorrente'),
          content: const Text(
            'Escolha se a alteração vale apenas para este lançamento ou para as contas em aberto a partir deste mês. Contas pagas não serão alteradas pela edição da recorrência.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Só este lançamento'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Próximos em aberto'),
            ),
          ],
        ),
      );
      if (scope == null || !mounted) return;
      editSeries = scope;
    }
    if (!mounted) return;
    final period = _period;
    final draft = await showModalBottomSheet<ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExpenseEditor(
        period: period,
        origins: _origins,
        expense: expense,
        seriesEdit: editSeries,
        now: _now,
      ),
    );
    if (draft == null || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      if (expense != null) {
        final edited = expense.copyWith(
          origem: draft.name,
          valor: draft.amount,
          vencimento: draft.due,
          categoria: draft.category,
        );
        if (editSeries) {
          await _repository.atualizarRecorrencia(
            expense.recorrenciaId!,
            edited,
          );
        } else {
          await _repository.updateGasto(edited);
        }
      } else {
        final base = Gasto(
          origem: draft.name,
          valor: draft.amount,
          pago: false,
          mes: period.month,
          ano: period.year,
          createdAt: _now.toIso8601String(),
          categoria: draft.category,
          vencimento: draft.due,
        );
        if (draft.recurring) {
          await _repository.criarRecorrencia(base, now: _now);
        } else if (draft.installments > 1) {
          await _repository.criarParcelamento(base, draft.installments);
        } else {
          await _repository.salvarSomandoSeExistir(base);
        }
      }
      if (!mounted) return;
      await _load(quiet: true);
      _message(
        expense != null
            ? 'Lançamento atualizado.'
            : draft.recurring
            ? 'Conta mensal criada.'
            : draft.installments > 1
            ? '${draft.installments} parcelas adicionadas.'
            : 'Lançamento adicionado.',
      );
    } catch (_) {
      _message(
        'Não foi possível salvar. Confira os lançamentos e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<Gasto>> _reloadPlan(String group) async {
    final rows = await _repository.getParcelas(group);
    return rows;
  }

  Future<void> _installments(Gasto expense) async {
    try {
      final rows = await _repository.getParcelas(expense.parcelaGrupo!);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => InstallmentDetails(
            expenses: rows,
            reference: expense,
            onPay: (g) async {
              await _repository.atualizarPago(g.id!, true);
              if (mounted) await _load(quiet: true);
            },
            onReload: () => _reloadPlan(expense.parcelaGrupo!),
          ),
        ),
      );
    } catch (_) {
      _message('Não foi possível abrir o parcelamento.');
    }
  }

  Future<void> _stopRecurring(Gasto expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar repetição mensal?'),
        content: const Text(
          'Os próximos lançamentos em aberto, após este mês, serão removidos. Este mês e os pagamentos já registrados serão mantidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encerrar repetição'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await _repository.encerrarRecorrencia(
        expense.recorrenciaId!,
        expense.mes,
        expense.ano,
      );
      if (mounted) await _load(quiet: true);
      _message('Repetição encerrada.');
    } catch (_) {
      _message('Não foi possível encerrar a repetição.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// One-tap payment: the summary updates immediately, then syncs.
  Future<void> _setPaid(
    List<Gasto> expenses,
    bool paid, {
    bool undoable = true,
  }) async {
    if (_saving || expenses.isEmpty) return;
    final ids = {for (final g in expenses) g.id};
    setState(() {
      _saving = true;
      _setExpenses([
        for (final g in _expenses)
          ids.contains(g.id) ? g.copyWith(pago: paid) : g,
      ]);
    });
    try {
      for (final g in expenses) {
        await _repository.atualizarPago(g.id!, paid);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      await _load(quiet: true);
      _message(
        !paid
            ? 'Conta marcada em aberto.'
            : expenses.length == 1
            ? 'Pagamento registrado.'
            : '${expenses.length} contas marcadas como pagas.',
        action: undoable
            ? SnackBarAction(
                label: 'Desfazer',
                onPressed: () => _setPaid(
                  [for (final g in expenses) g.copyWith(pago: paid)],
                  !paid,
                  undoable: false,
                ),
              )
            : null,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _load(quiet: true);
      _message('Não foi possível atualizar o pagamento.');
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Gasto expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          '${expense.origem} · ${money(expense.valor)}\nEsta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FinanceColors.late),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await _repository.deleteGasto(expense.id!);
      if (mounted) await _load(quiet: true);
      _message('Lançamento excluído.');
    } catch (_) {
      _message('Não foi possível excluir o lançamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectPeriod() async {
    var year = _period.year;
    var month = _period.month;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: const Text('Selecionar período'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Ano anterior',
                    onPressed: year > 2000 ? () => change(() => year--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '$year',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Próximo ano',
                    onPressed: year < 2100 ? () => change(() => year++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(
                  12,
                  (i) => ChoiceChip(
                    label: Text(monthShort[i]),
                    selected: month == i + 1,
                    onSelected: (_) => change(() => month = i + 1),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await _changePeriod(DateTime(year, month));
    }
  }

  Future<void> _settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ConfiguracoesPage()),
    );
    if (mounted) await _load(quiet: true);
  }

  void _reminders() {
    final now = dateOnly(_now);
    final upcoming =
        _expenses
            .where(
              (g) =>
                  !g.pago &&
                  g.vencimento != null &&
                  daysBetween(now, g.vencimento!) <= 7,
            )
            .toList()
          ..sort(_compareDue);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Lembretes', style: FinanceText.title),
              const SizedBox(height: 4),
              const Text(
                'Contas vencidas e que vencem nos próximos 7 dias.',
                style: FinanceText.caption,
              ),
              const SizedBox(height: 14),
              if (upcoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Nada vencendo nos próximos dias.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FinanceColors.muted),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: ListCard(
                      children: [
                        for (final g in upcoming)
                          PayableRow(
                            gasto: g,
                            now: _now,
                            actions: ExpenseActions(
                              onEdit: () {
                                Navigator.pop(ctx);
                                _edit(g);
                              },
                              onPay: () {
                                Navigator.pop(ctx);
                                _setPaid([g], true);
                              },
                              onDelete: () {
                                Navigator.pop(ctx);
                                _delete(g);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _settings();
                },
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Configurar lembretes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openContas(FiltroStatus filter) => setState(() {
    _tab = 1;
    _contasFilter = filter;
    _contasReset++;
  });

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      1 => _withStatus(
        (content) => ContasView(
          key: ValueKey('contas-$_contasReset'),
          expenses: _expenses,
          now: _now,
          period: _period,
          initialFilter: _contasFilter,
          onPeriod: _changePeriod,
          onPickPeriod: _selectPeriod,
          actionsFor: _actionsFor,
          onAdd: () => _edit(),
          status: content,
        ),
      ),
      2 => FuturoView(
        plan: _plan,
        error: _planError,
        onRetry: _loadPlan,
        onOpenPlan: _installments,
      ),
      _ => _home(),
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(quiet: true),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: body,
            ),
          ),
        ),
      ),
      bottomNavigationBar: FinanceBottomBar(
        index: _tab,
        busy: _saving,
        onSelect: (i) {
          if (i == 3) {
            _settings();
          } else {
            setState(() {
              if (i == 1 && _tab != 1) {
                _contasFilter = FiltroStatus.todos;
                _contasReset++;
              }
              _tab = i;
            });
          }
        },
        onAdd: () => _edit(),
      ),
    );
  }

  /// Loading/error placeholder shared by the month-based tabs.
  Widget _withStatus(Widget Function(Widget? status) builder) {
    if (_loading) {
      return builder(
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return builder(
        FinanceEmptyState(
          title: 'Não foi possível carregar',
          message: _error!,
          action: 'Tentar novamente',
          onAction: _load,
        ),
      );
    }
    return builder(null);
  }

  Widget _home() {
    final s = _summary;
    final isCurrent =
        _period.year == _now.year && _period.month == _now.month;
    final children = <Widget>[
      Row(
        children: [
          Transform.translate(
            offset: const Offset(-10, 0),
            child: MonthArrow(
              period: _period,
              forward: false,
              onChanged: _changePeriod,
            ),
          ),
          Flexible(
            child: Transform.translate(
              offset: const Offset(-10, 0),
              child: Semantics(
                button: true,
                label: 'Selecionar período',
                child: InkWell(
                  onTap: _selectPeriod,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monthNames[_period.month - 1],
                          style: FinanceText.title.copyWith(fontSize: 22),
                        ),
                        Text(
                          isCurrent
                              ? '${_period.year} · hoje, ${shortDate(_now)}'
                              : '${_period.year}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: FinanceColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-10, 0),
            child: MonthArrow(
              period: _period,
              forward: true,
              onChanged: _changePeriod,
            ),
          ),
          const Spacer(),
          if (!isCurrent)
            TextButton(
              onPressed: () => _changePeriod(DateTime(_now.year, _now.month)),
              child: const Text('Hoje'),
            ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Lembretes',
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: FinanceColors.line),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _reminders,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.notifications_none,
                    size: 21,
                    semanticLabel: 'Lembretes',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
    if (_loading || _error != null) {
      children.add(_withStatus((status) => status!));
    } else if (s == null || _expenses.isEmpty) {
      children.add(
        FinanceEmptyState(
          leading: const AppLogo(size: 48),
          title: 'Seu mês começa aqui',
          message:
              'Adicione sua primeira conta para acompanhar valores e vencimentos.',
          action: 'Adicionar primeira conta',
          onAction: () => _edit(),
        ),
      );
    } else {
      children.addAll(_homeContent(s));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: children,
    );
  }

  List<Widget> _homeContent(HomeSummary s) {
    const maxOpen = 8, maxPaid = 4;
    final month = monthNames[_period.month - 1].toLowerCase();
    final pct = s.total == 0 ? 0 : (s.paid / s.total * 100).round();
    return [
      _HeroCard(summary: s, month: month, percent: pct),
      if (s.late.isNotEmpty) ...[
        const SizedBox(height: 14),
        _LateBanner(
          title: s.late.length == 1
              ? '${s.late.first.origem} ${dueStatus(s.late.first, _now).label.toLowerCase()}'
              : '${s.late.length} contas vencidas',
          amount: s.lateTotal,
          onOpen: () => _openContas(FiltroStatus.vencidos),
          onPay: _saving ? null : () => _setPaid(s.late, true),
        ),
      ],
      FinanceSection(
        title: 'A pagar',
        count: s.open.length,
        action: TextButton(
          onPressed: () => _openContas(FiltroStatus.todos),
          child: const Text('Ver todas'),
        ),
      ),
      if (s.open.isEmpty)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FinanceColors.line),
          ),
          child: Text(
            'Tudo pago em $month.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: FinanceColors.paid,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      else
        ListCard(
          children: [
            for (final g in s.open.take(maxOpen))
              PayableRow(gasto: g, now: _now, actions: _actionsFor(g)),
          ],
        ),
      if (s.open.length > maxOpen)
        _MoreLink(
          label: 'Ver mais ${s.open.length - maxOpen} a pagar',
          onTap: () => _openContas(FiltroStatus.abertos),
        ),
      if (s.paidRows.isNotEmpty) ...[
        FinanceSection(title: 'Pagas', count: s.paidRows.length),
        ListCard(
          children: [
            for (final g in s.paidRows.take(maxPaid))
              PayableRow(gasto: g, now: _now, actions: _actionsFor(g)),
          ],
        ),
        if (s.paidRows.length > maxPaid)
          _MoreLink(
            label: 'Ver todas as ${s.paidRows.length} pagas',
            onTap: () => _openContas(FiltroStatus.pagos),
          ),
      ],
      const SizedBox(height: 16),
      _CategoryBreakdown(summary: s),
    ];
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(onPressed: onTap, child: Text(label)),
  );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.summary,
    required this.month,
    required this.percent,
  });
  final HomeSummary summary;
  final String month;
  final int percent;
  @override
  Widget build(BuildContext context) {
    final s = summary;
    final total = s.total == 0 ? 1.0 : s.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: FinanceColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Falta pagar em $month',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.onInkMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: FinanceColors.lime,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$percent% pago',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              s.remaining,
              size: 52,
              color: Colors.white,
              secondary: FinanceColors.onInkMuted,
            ),
          ),
          const SizedBox(height: 16),
          SegmentBar(
            parts: [
              (s.paid / total, FinanceColors.lime),
              (s.lateTotal / total, FinanceColors.coral),
            ],
            semanticsLabel:
                '$percent% do valor pago, ${(s.lateTotal / total * 100).round()}% vencido',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroStat(
                label: 'Pago',
                value: money(s.paid),
                dot: FinanceColors.lime,
              ),
              _HeroStat(
                label: 'Vencido',
                value: money(s.lateTotal),
                dot: FinanceColors.coral,
              ),
              _HeroStat(label: 'Total do mês', value: money(s.total)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.dot});
  final String label, value;
  final Color? dot;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: FinanceColors.onInkMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: FinanceFonts.tabular,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LateBanner extends StatelessWidget {
  const _LateBanner({
    required this.title,
    required this.amount,
    required this.onOpen,
    required this.onPay,
  });
  final String title;
  final double amount;
  final VoidCallback onOpen;
  final VoidCallback? onPay;
  @override
  Widget build(BuildContext context) => Material(
    color: FinanceColors.lateBg,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: FinanceColors.late,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FinanceColors.lateText,
                    ),
                  ),
                  Text(
                    '${money(amount)} em atraso',
                    style: const TextStyle(
                      fontSize: 13,
                      color: FinanceColors.late,
                      fontFeatures: FinanceFonts.tabular,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FinanceColors.late,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onPay,
              child: const Text('Já paguei'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.summary});
  final HomeSummary summary;
  static const _colors = [
    Color(0xFF14161A),
    Color(0xFF4A4D53),
    Color(0xFF7E8189),
    Color(0xFFAEB0B5),
    Color(0xFFD4D5D0),
  ];
  @override
  Widget build(BuildContext context) {
    final total = summary.total == 0 ? 1.0 : summary.total;
    final cats = summary.categories;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FinanceColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Para onde vai', style: FinanceText.section),
          ),
          const SizedBox(height: 12),
          SegmentBar(
            height: 12,
            track: FinanceColors.chip,
            parts: [
              for (var i = 0; i < cats.length; i++)
                (cats[i].$2 / total, _colors[i % _colors.length]),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < cats.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colors[i % _colors.length],
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: FinanceColors.outline),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cats[i].$1,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(cats[i].$2 / total * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: FinanceColors.muted,
                        fontFeatures: FinanceFonts.tabular,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 104,
                    child: Text(
                      money(cats[i].$2),
                      textAlign: TextAlign.right,
                      style: FinanceText.amount.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Contas tab. Owns its filters so typing in the search only rebuilds
/// this subtree; filtered/grouped rows are cached between builds.
class ContasView extends StatefulWidget {
  const ContasView({
    super.key,
    required this.expenses,
    required this.now,
    required this.period,
    required this.onPeriod,
    required this.actionsFor,
    required this.onAdd,
    this.onPickPeriod,
    this.initialFilter = FiltroStatus.todos,
    this.status,
  });
  final List<Gasto> expenses;
  final DateTime now, period;
  final ValueChanged<DateTime> onPeriod;
  final VoidCallback? onPickPeriod;
  final ExpenseActions Function(Gasto) actionsFor;
  final VoidCallback onAdd;
  final FiltroStatus initialFilter;

  /// Loading/error widget shown in place of the list.
  final Widget? status;
  @override
  State<ContasView> createState() => _ContasViewState();
}

enum _Group { vencidas, semana, depois, pagas }

class _ContasViewState extends State<ContasView> {
  final _search = TextEditingController();
  late FiltroStatus _filter = widget.initialFilter;
  String? _category;
  Timer? _debounce;
  String _query = '';

  // Cache.
  List<String> _categories = [];
  Map<FiltroStatus, int> _counts = {};
  List<(_Group, List<Gasto>, double)> _groups = [];

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(ContasView old) {
    super.didUpdateWidget(old);
    if (!identical(old.expenses, widget.expenses) || old.now != widget.now) {
      if (_category != null &&
          !widget.expenses.any((g) => g.categoria == _category)) {
        _category = null;
      }
      _recompute();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  _Group _groupOf(Gasto g) {
    if (g.pago) return _Group.pagas;
    if (g.vencidoEm(widget.now)) return _Group.vencidas;
    final due = g.vencimento;
    if (due != null && daysBetween(widget.now, due) <= 6) return _Group.semana;
    return _Group.depois;
  }

  void _recompute() {
    final all = widget.expenses;
    _categories = (all.map((g) => g.categoria).toSet().toList()..sort());
    final q = _query.trim().toLowerCase();
    final base = all
        .where(
          (g) =>
              (q.isEmpty || g.origem.toLowerCase().contains(q)) &&
              (_category == null || g.categoria == _category),
        )
        .toList();
    bool matches(Gasto g, FiltroStatus f) => switch (f) {
      FiltroStatus.todos => true,
      FiltroStatus.abertos => !g.pago,
      FiltroStatus.pagos => g.pago,
      FiltroStatus.vencidos => g.vencidoEm(widget.now),
    };
    _counts = {
      for (final f in FiltroStatus.values)
        f: base.where((g) => matches(g, f)).length,
    };
    final visible = base.where((g) => matches(g, _filter));
    final grouped = <_Group, List<Gasto>>{};
    for (final g in visible) {
      grouped.putIfAbsent(_groupOf(g), () => []).add(g);
    }
    _groups = [
      for (final group in _Group.values)
        if (grouped[group] case final rows?)
          (
            group,
            rows..sort(_compareDue),
            rows.fold<double>(0, (s, g) => s + g.valor),
          ),
    ];
  }

  void _update(VoidCallback change) => setState(() {
    change();
    _recompute();
  });

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _update(() => _query = value);
    });
  }

  void _clear() => _update(() {
    _debounce?.cancel();
    _search.clear();
    _query = '';
    _category = null;
    _filter = FiltroStatus.todos;
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (widget.status != null) {
      rows.add(widget.status!);
    } else if (widget.expenses.isEmpty) {
      rows.add(
        FinanceEmptyState(
          title: 'Seu mês começa aqui',
          message:
              'Adicione sua primeira conta para acompanhar valores e vencimentos.',
          action: 'Adicionar primeira conta',
          onAction: widget.onAdd,
        ),
      );
    } else if (_groups.isEmpty) {
      rows.add(
        FinanceEmptyState(
          title: 'Nenhuma conta encontrada',
          message: 'Nenhuma conta com esses filtros.',
          action: 'Limpar filtros',
          onAction: _clear,
        ),
      );
    } else {
      for (final (group, items, total) in _groups) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      switch (group) {
                        _Group.vencidas => 'VENCIDAS',
                        _Group.semana => 'ESTA SEMANA',
                        _Group.depois => 'ATÉ O FIM DO MÊS',
                        _Group.pagas => 'PAGAS',
                      },
                      style: FinanceText.overline.copyWith(
                        color: switch (group) {
                          _Group.vencidas => FinanceColors.late,
                          _Group.pagas => FinanceColors.paid,
                          _ => FinanceColors.body,
                        },
                      ),
                    ),
                  ),
                ),
                Text(
                  money(total),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FinanceColors.muted,
                    fontFeatures: FinanceFonts.tabular,
                  ),
                ),
              ],
            ),
          ),
        );
        rows.add(
          ListCard(
            children: [
              for (final g in items)
                ExpenseRow(
                  gasto: g,
                  now: widget.now,
                  actions: widget.actionsFor(g),
                ),
            ],
          ),
        );
      }
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text('Contas', style: FinanceText.title),
                    ),
                  ),
                  MonthStepper(
                    period: widget.period,
                    onChanged: widget.onPeriod,
                    onPick: widget.onPickPeriod,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar conta ou instituição',
                  prefixIcon: Icon(Icons.search, color: FinanceColors.muted),
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final f in FiltroStatus.values) ...[
                    CountChip(
                      label: switch (f) {
                        FiltroStatus.todos => 'Todas',
                        FiltroStatus.abertos => 'A pagar',
                        FiltroStatus.vencidos => 'Vencidas',
                        FiltroStatus.pagos => 'Pagas',
                      },
                      count: _counts[f] ?? 0,
                      selected: _filter == f,
                      onTap: () => _update(() => _filter = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_categories.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final c in [null, ..._categories])
                      _CategoryChip(
                        label: c ?? 'Todas',
                        selected: _category == c,
                        onTap: () => _update(() => _category = c),
                      ),
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverList.list(children: rows),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Semantics(
      button: true,
      selected: selected,
      label: 'Categoria $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? FinanceColors.chipActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? FinanceColors.ink : FinanceColors.body,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Início · Contas · (+) · Futuro · Ajustes. Ajustes opens its own page.
class FinanceBottomBar extends StatelessWidget {
  const FinanceBottomBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onAdd,
    this.busy = false,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    Widget item(int i, String label, IconData icon, IconData active) =>
        Expanded(
          child: _NavItem(
            label: label,
            icon: index == i ? active : icon,
            selected: index == i,
            onTap: () => onSelect(i),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: FinanceColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item(0, 'Início', Icons.home_outlined, Icons.home),
              item(1, 'Contas', Icons.list, Icons.list),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -16),
                    child: Tooltip(
                      message: 'Novo lançamento',
                      child: Semantics(
                        button: true,
                        label: 'Novo lançamento',
                        excludeSemantics: true,
                        child: Material(
                          color: FinanceColors.ink,
                          elevation: 3,
                          shadowColor: const Color(0x4014161A),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: busy ? null : onAdd,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: FinanceColors.lime,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.add,
                                      size: 28,
                                      color: FinanceColors.lime,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              item(2, 'Futuro', Icons.bar_chart, Icons.bar_chart),
              item(3, 'Ajustes', Icons.tune, Icons.tune),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
  Widget build(BuildContext context) {
    final color = selected ? FinanceColors.ink : FinanceColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
