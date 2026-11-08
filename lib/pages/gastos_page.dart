import 'package:flutter/material.dart';

import '../data/gastos_repository.dart';
import '../data/preferences_service.dart';
import '../models/gasto.dart';
import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';
import '../utils/installment_helper.dart';
import '../widgets/expense_editor.dart';
import 'configuracoes_page.dart';

enum FiltroStatus { todos, abertos, pagos, vencidos }

enum Ordenacao { vencimento, alfabetica, maiorValor, menorValor, recentes }

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
  final _search = TextEditingController();
  late DateTime _period;
  List<Gasto> _expenses = [];
  List<String> _origins = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _tab = 0;
  int _loadGeneration = 0;
  FiltroStatus _filter = FiltroStatus.todos;
  Ordenacao _order = Ordenacao.vencimento;
  static const _months = [
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
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  String get _periodLabel => '${_months[_period.month - 1]} ${_period.year}';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? GastosRepository();
    _period = DateTime(_now.year, _now.month);
    _initialize();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _repository.getGastosDoMes(_period.month, _period.year),
        _repository.getOrigensDistintas(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _expenses = result[0] as List<Gasto>;
        _origins = result[1] as List<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar este mês. Seus dados não foram alterados.';
      });
    }
  }

  Future<void> _changePeriod(DateTime period) async {
    setState(() => _period = period);
    await _load();
    try {
      await _preferences.salvarMesAnoSelecionado(period.month, period.year);
    } catch (_) {
      if (mounted) _message('O período não pôde ser salvo nas preferências.');
    }
  }

  List<Gasto> get _filtered {
    final query = _search.text.trim().toLowerCase();
    final result = _expenses
        .where(
          (g) =>
              g.origem.toLowerCase().contains(query) &&
              switch (_filter) {
                FiltroStatus.todos => true,
                FiltroStatus.abertos => !g.pago,
                FiltroStatus.pagos => g.pago,
                FiltroStatus.vencidos => g.vencidoEm(_now),
              },
        )
        .toList();
    result.sort(
      (a, b) => switch (_order) {
        Ordenacao.alfabetica => a.origem.toLowerCase().compareTo(
          b.origem.toLowerCase(),
        ),
        Ordenacao.maiorValor => b.valor.compareTo(a.valor),
        Ordenacao.menorValor => a.valor.compareTo(b.valor),
        Ordenacao.recentes => b.createdAt.compareTo(a.createdAt),
        Ordenacao.vencimento => _compareDue(a, b),
      },
    );
    return result;
  }

  int _compareDue(Gasto a, Gasto b) {
    if (a.pago != b.pago) return a.pago ? 1 : -1;
    return (a.vencimento ?? DateTime(9999)).compareTo(
      b.vencimento ?? DateTime(9999),
    );
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _edit([Gasto? expense]) async {
    final draft = await showModalBottomSheet<ExpenseDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          ExpenseEditor(period: _period, origins: _origins, expense: expense),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (expense != null) {
        if (await _repository.existeGastoComOrigem(
          draft.name,
          expense.mes,
          expense.ano,
          excludeId: expense.id,
        )) {
          _message('Já existe uma conta com esse nome neste mês.');
          return;
        }
        await _repository.updateGasto(
          expense.copyWith(
            origem: draft.name,
            valor: draft.amount,
            vencimento: draft.due,
          ),
        );
      } else {
        final parts = InstallmentHelper.splitAmount(
          draft.amount,
          draft.installments,
        );
        for (var index = 0; index < parts.length; index++) {
          final period = InstallmentHelper.addMonths(
            _period.month,
            _period.year,
            index,
          );
          final lastDay = DateTime(
            draft.due.year,
            draft.due.month + index + 1,
            0,
          ).day;
          await _repository.salvarSomandoSeExistir(
            Gasto(
              origem: draft.name,
              valor: parts[index],
              pago: false,
              mes: period.mes,
              ano: period.ano,
              createdAt: _now.toIso8601String(),
              vencimento: DateTime(
                draft.due.year,
                draft.due.month + index,
                draft.due.day.clamp(1, lastDay),
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      await _load();
      _message(
        expense != null
            ? 'Lançamento atualizado.'
            : draft.installments > 1
            ? '${draft.installments} parcelas adicionadas.'
            : 'Lançamento adicionado.',
      );
    } catch (_) {
      _message(
        'Não foi possível salvar. Confira os lançamentos antes de tentar novamente.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pay(Gasto expense) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repository.atualizarPago(expense.id!, !expense.pago);
      if (mounted) await _load();
      _message(
        expense.pago ? 'Conta marcada em aberto.' : 'Pagamento registrado.',
      );
    } catch (_) {
      _message('Não foi possível atualizar o pagamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
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
            style: FilledButton.styleFrom(backgroundColor: FinanceColors.red),
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
      if (mounted) await _load();
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
                children: List.generate(
                  12,
                  (i) => ChoiceChip(
                    label: Text(_months[i].substring(0, 3)),
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

  void _summary() {
    final total = _expenses.fold<double>(0, (v, g) => v + g.valor);
    final grouped = <String, double>{};
    for (final g in _expenses) {
      grouped.update(g.origem, (v) => v + g.valor, ifAbsent: () => g.valor);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Text(
              'Resumo do mês',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _periodLabel,
              style: const TextStyle(color: FinanceColors.muted),
            ),
            const SizedBox(height: 20),
            MonthlyOverview(
              gastos: _expenses,
              onDetails: () => Navigator.pop(ctx),
            ),
            const FinanceSection(
              title: 'Distribuição por origem',
              subtitle: 'Valores pagos e em aberto no período',
            ),
            if (entries.isEmpty)
              const Text('Adicione um lançamento para ver a distribuição.'),
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(money(e.value)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value / total,
                      minHeight: 5,
                      color: FinanceColors.ink,
                      backgroundColor: FinanceColors.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ConfiguracoesPage()),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered;
    final overview = _tab == 0;
    final overdue = _expenses.where((g) => g.vencidoEm(_now)).toList();
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.account_balance_outlined, size: 22),
        leadingWidth: 48,
        titleSpacing: 0,
        title: const Text('FinanTech'),
        actions: [
          IconButton.filled(
            tooltip: 'Adicionar gasto',
            onPressed: _saving ? null : () => _edit(),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: _settings,
            icon: const Icon(Icons.tune_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == 2) {
            _settings();
          } else {
            setState(() {
              _tab = i;
              _filter = FiltroStatus.todos;
              _search.clear();
            });
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Visão geral',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Lançamentos',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            label: 'Ajustes',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverList.list(
                      children: [
                        Text(
                          overview ? 'Suas contas, em dia.' : 'Lançamentos',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.9,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          overview
                              ? 'Uma visão clara do seu mês.'
                              : 'Acompanhe cada conta e pagamento.',
                          style: const TextStyle(
                            color: FinanceColors.muted,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _selectPeriod,
                                icon: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                ),
                                label: Text(_periodLabel),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Mês anterior',
                              onPressed: () => _changePeriod(
                                DateTime(_period.year, _period.month - 1),
                              ),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              tooltip: 'Próximo mês',
                              onPressed: () => _changePeriod(
                                DateTime(_period.year, _period.month + 1),
                              ),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        if (_period.month != _now.month ||
                            _period.year != _now.year)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _changePeriod(
                                DateTime(_now.year, _now.month),
                              ),
                              child: const Text('Voltar ao mês atual'),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null)
                          FinanceEmptyState(
                            title: 'Não foi possível carregar',
                            message: _error!,
                            action: 'Tentar novamente',
                            onAction: _load,
                          )
                        else ...[
                          if (overview) ...[
                            MonthlyOverview(
                              gastos: _expenses,
                              onDetails: _summary,
                            ),
                            if (overdue.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Material(
                                  color: const Color(0xFFFFF1F0),
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    onTap: () => setState(() {
                                      _tab = 1;
                                      _filter = FiltroStatus.vencidos;
                                      _search.clear();
                                    }),
                                    leading: const Icon(
                                      Icons.error_outline,
                                      color: FinanceColors.red,
                                    ),
                                    title: Text(
                                      '${overdue.length} ${overdue.length == 1 ? 'conta vencida' : 'contas vencidas'}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: FinanceColors.red,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${money(overdue.fold<double>(0, (v, g) => v + g.valor))} para regularizar',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: FinanceColors.red,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                      color: FinanceColors.red,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          FinanceSection(
                            title: overview
                                ? 'Contas do mês'
                                : 'Seus lançamentos',
                            subtitle:
                                '${visible.length} ${visible.length == 1 ? 'lançamento' : 'lançamentos'}',
                            action: overview
                                ? TextButton(
                                    onPressed: () => setState(() => _tab = 1),
                                    child: const Text('Ver todas'),
                                  )
                                : null,
                          ),
                          if (!overview) ...[
                            TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'Buscar por nome ou instituição',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: FiltroStatus.values
                                    .map(
                                      (f) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(switch (f) {
                                            FiltroStatus.todos => 'Todas',
                                            FiltroStatus.abertos => 'Em aberto',
                                            FiltroStatus.pagos => 'Pagas',
                                            FiltroStatus.vencidos => 'Vencidas',
                                          }),
                                          selected: _filter == f,
                                          onSelected: (_) =>
                                              setState(() => _filter = f),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: PopupMenuButton<Ordenacao>(
                                tooltip: 'Ordenar lançamentos',
                                initialValue: _order,
                                onSelected: (o) => setState(() => _order = o),
                                itemBuilder: (_) => Ordenacao.values
                                    .map(
                                      (o) => PopupMenuItem(
                                        value: o,
                                        child: Text(_orderLabel(o)),
                                      ),
                                    )
                                    .toList(),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.sort, size: 17),
                                      const SizedBox(width: 6),
                                      Text(
                                        _orderLabel(_order),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.expand_more, size: 17),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  if (!_loading && _error == null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: visible.isEmpty
                          ? SliverToBoxAdapter(
                              child: FinanceEmptyState(
                                title: _expenses.isEmpty
                                    ? 'Seu mês começa aqui'
                                    : 'Nenhuma conta encontrada',
                                message: _expenses.isEmpty
                                    ? 'Adicione sua primeira conta para acompanhar valores e vencimentos.'
                                    : 'Tente outro nome ou altere os filtros.',
                                action: _expenses.isEmpty
                                    ? 'Adicionar primeira conta'
                                    : 'Limpar filtros',
                                onAction: _expenses.isEmpty
                                    ? () => _edit()
                                    : () => setState(() {
                                        _search.clear();
                                        _filter = FiltroStatus.todos;
                                      }),
                              ),
                            )
                          : SliverList.builder(
                              itemCount: overview
                                  ? visible.length.clamp(0, 5)
                                  : visible.length,
                              itemBuilder: (context, i) => Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    bottom: const BorderSide(
                                      color: FinanceColors.line,
                                    ),
                                    left: const BorderSide(
                                      color: FinanceColors.line,
                                    ),
                                    right: const BorderSide(
                                      color: FinanceColors.line,
                                    ),
                                    top: i == 0
                                        ? const BorderSide(
                                            color: FinanceColors.line,
                                          )
                                        : BorderSide.none,
                                  ),
                                ),
                                child: ExpenseRow(
                                  gasto: visible[i],
                                  now: _now,
                                  onEdit: () => _edit(visible[i]),
                                  onPay: () => _pay(visible[i]),
                                  onDelete: () => _delete(visible[i]),
                                ),
                              ),
                            ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 104)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _orderLabel(Ordenacao order) => switch (order) {
    Ordenacao.vencimento => 'Por vencimento',
    Ordenacao.alfabetica => 'Nome de A a Z',
    Ordenacao.maiorValor => 'Maior valor',
    Ordenacao.menorValor => 'Menor valor',
    Ordenacao.recentes => 'Mais recentes',
  };
}
