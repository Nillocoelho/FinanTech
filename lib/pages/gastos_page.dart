import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/gastos_repository.dart';
import '../data/preferences_service.dart';
import '../models/gasto.dart';
import '../utils/currency_helper.dart';
import 'configuracoes_page.dart';

enum FiltroStatus { todos, abertos, pagos }
enum Ordenacao { recentes, alfabetica, maiorValor, menorValor }

class GastosPage extends StatefulWidget {
  const GastosPage({super.key});

  @override
  State<GastosPage> createState() => _GastosPageState();
}

class _GastosPageState extends State<GastosPage> {
  final GastosRepository _repository = GastosRepository();
  final PreferencesService _prefsService = PreferencesService();
  final TextEditingController _origemController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  int _mesSelecionado = DateTime.now().month;
  int _anoSelecionado = DateTime.now().year;
  List<Gasto> _gastos = [];
  Map<String, double> _totaisPorOrigem = {};
  double _totalEmAberto = 0.0;
  bool _isLoading = true;
  bool _prefsLoaded = false;
  List<String> _origensDisponiveis = [];
  FiltroStatus _filtroStatus = FiltroStatus.todos;
  Ordenacao _ordenacao = Ordenacao.alfabetica;
  bool _totalizadorExpandido = false;

  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  static const List<String> _nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  @override
  void initState() {
    super.initState();
    _carregarPreferenciasEDados();
  }

  @override
  void dispose() {
    _origemController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  Future<void> _carregarPreferenciasEDados() async {
    if (!_prefsLoaded) {
      final mesAno = await _prefsService.getMesAnoSelecionado();
      setState(() {
        _mesSelecionado = mesAno.mes;
        _anoSelecionado = mesAno.ano;
        _prefsLoaded = true;
      });
    }
    await _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getGastosDoMes(_mesSelecionado, _anoSelecionado),
        _repository.getTotaisPorOrigemDoMes(_mesSelecionado, _anoSelecionado),
        _repository.getTotalDoMes(_mesSelecionado, _anoSelecionado),
        _repository.getOrigensDistintas(),
      ]);
      setState(() {
        _gastos = results[0] as List<Gasto>;
        _totaisPorOrigem = results[1] as Map<String, double>;
        _totalEmAberto = results[2] as double;
        _origensDisponiveis = results[3] as List<String>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _mostrarErro('Erro ao carregar dados: $e');
    }
  }

  List<Gasto> get _gastosFiltrados {
    // Primeiro filtra
    var resultado = _gastos.where((gasto) {
      if (_filtroStatus == FiltroStatus.abertos && gasto.pago) return false;
      if (_filtroStatus == FiltroStatus.pagos && !gasto.pago) return false;
      return true;
    }).toList();
    
    // Depois ordena
    switch (_ordenacao) {
      case Ordenacao.recentes:
        // Já vem ordenado por createdAt DESC do banco
        break;
      case Ordenacao.alfabetica:
        resultado.sort((a, b) => a.origem.toLowerCase().compareTo(b.origem.toLowerCase()));
        break;
      case Ordenacao.maiorValor:
        resultado.sort((a, b) => b.valor.compareTo(a.valor));
        break;
      case Ordenacao.menorValor:
        resultado.sort((a, b) => a.valor.compareTo(b.valor));
        break;
    }
    
    return resultado;
  }

  Future<void> _adicionarGasto() async {
    if (!_formKey.currentState!.validate()) return;
    final origem = _origemController.text.trim();
    final valor = CurrencyHelper.parseFromCurrency(_valorController.text);
    if (valor <= 0) {
      _mostrarErro('Por favor, insira um valor válido.');
      return;
    }
    // Verificar se já existe um gasto com a mesma origem neste mês/ano
    final duplicado = await _repository.existeGastoComOrigem(
      origem, _mesSelecionado, _anoSelecionado);
    if (duplicado) {
      _mostrarErro('Já existe um gasto com o nome "$origem" neste mês.');
      return;
    }
    final novoGasto = Gasto(
      origem: origem,
      valor: valor,
      pago: false,
      mes: _mesSelecionado,
      ano: _anoSelecionado,
      createdAt: DateTime.now().toIso8601String(),
    );
    try {
      await _repository.insertGasto(novoGasto);
      _origemController.clear();
      _valorController.clear();
      await _carregarDados();
      _mostrarSucesso('Gasto adicionado com sucesso!');
    } catch (e) {
      _mostrarErro('Erro ao adicionar gasto: $e');
    }
  }

  Future<void> _togglePago(Gasto gasto) async {
    try {
      await _repository.atualizarPago(gasto.id!, !gasto.pago);
      await _carregarDados();
      final status = !gasto.pago ? 'pago' : 'em aberto';
      _mostrarSucesso('Gasto marcado como $status');
    } catch (e) {
      _mostrarErro('Erro ao atualizar gasto: $e');
    }
  }

  Future<void> _confirmarExclusao(Gasto gasto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: Text(
            'Excluir gasto de ${_currencyFormat.format(gasto.valor)} para "${gasto.origem}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmado == true) {
      try {
        await _repository.deleteGasto(gasto.id!);
        await _carregarDados();
        _mostrarSucesso('Gasto excluído com sucesso!');
      } catch (e) {
        _mostrarErro('Erro ao excluir gasto: $e');
      }
    }
  }

  Future<void> _editarGasto(Gasto gasto) async {
    final origemCtrl = TextEditingController(text: gasto.origem);
    final valorCtrl =
        TextEditingController(text: CurrencyHelper.formatToCurrency(gasto.valor));
    final formKey = GlobalKey<FormState>();
    final resultado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Editar Gasto', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: origemCtrl,
                decoration: const InputDecoration(
                    labelText: 'Origem', border: OutlineInputBorder()),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe a origem' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: valorCtrl,
                decoration: const InputDecoration(
                    labelText: 'Valor',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ '),
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Informe o valor';
                  if (CurrencyHelper.parseFromCurrency(v) <= 0) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'))),
                const SizedBox(width: 16),
                Expanded(
                    child: FilledButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
                        },
                        child: const Text('Salvar'))),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (resultado == true) {
      try {
        final novaOrigem = origemCtrl.text.trim();
        // Verificar duplicados apenas se a origem foi alterada
        if (novaOrigem.toLowerCase() != gasto.origem.toLowerCase()) {
          final duplicado = await _repository.existeGastoComOrigem(
            novaOrigem, gasto.mes, gasto.ano, excludeId: gasto.id);
          if (duplicado) {
            _mostrarErro('Já existe um gasto com o nome "$novaOrigem" neste mês.');
            origemCtrl.dispose();
            valorCtrl.dispose();
            return;
          }
        }
        final gastoAtualizado = gasto.copyWith(
            origem: novaOrigem,
            valor: CurrencyHelper.parseFromCurrency(valorCtrl.text));
        await _repository.updateGasto(gastoAtualizado);
        await _carregarDados();
        _mostrarSucesso('Gasto atualizado com sucesso!');
      } catch (e) {
        _mostrarErro('Erro ao atualizar gasto: $e');
      }
    }
    origemCtrl.dispose();
    valorCtrl.dispose();
  }

  void _mostrarErro(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _mostrarSucesso(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2)));

  bool get _isMesAtual =>
      _mesSelecionado == DateTime.now().month && _anoSelecionado == DateTime.now().year;

  void _irParaMesAtual() {
    setState(() {
      _mesSelecionado = DateTime.now().month;
      _anoSelecionado = DateTime.now().year;
    });
    _salvarPreferenciasECarregar();
  }

  void _proximoMes() {
    setState(() {
      if (_mesSelecionado == 12) {
        _mesSelecionado = 1;
        _anoSelecionado++;
      } else {
        _mesSelecionado++;
      }
    });
    _salvarPreferenciasECarregar();
  }

  void _mesAnterior() {
    setState(() {
      if (_mesSelecionado == 1) {
        _mesSelecionado = 12;
        _anoSelecionado--;
      } else {
        _mesSelecionado--;
      }
    });
    _salvarPreferenciasECarregar();
  }

  Future<void> _salvarPreferenciasECarregar() async {
    await _prefsService.salvarMesAnoSelecionado(_mesSelecionado, _anoSelecionado);
    await _carregarDados();
  }

  bool get _temFiltrosAtivos => _filtroStatus != FiltroStatus.todos || _ordenacao != Ordenacao.alfabetica;

  String get _textoOrdenacao {
    switch (_ordenacao) {
      case Ordenacao.recentes:
        return 'Recentes';
      case Ordenacao.alfabetica:
        return 'A-Z';
      case Ordenacao.maiorValor:
        return 'Maior valor';
      case Ordenacao.menorValor:
        return 'Menor valor';
    }
  }

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.filter_list),
            const SizedBox(width: 8),
            Text('Filtros e Ordenação', style: Theme.of(ctx).textTheme.titleLarge),
            const Spacer(),
            if (_temFiltrosAtivos)
              TextButton(
                onPressed: () {
                  setState(() {
                    _filtroStatus = FiltroStatus.todos;
                    _ordenacao = Ordenacao.alfabetica;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Limpar'),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Status:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            _buildChipFiltroModal('Todos', FiltroStatus.todos, ctx),
            _buildChipFiltroModal('Em aberto', FiltroStatus.abertos, ctx),
            _buildChipFiltroModal('Pagos', FiltroStatus.pagos, ctx),
          ]),
          const SizedBox(height: 20),
          const Text('Ordenar por:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _buildChipOrdenacaoModal('Recentes', Ordenacao.recentes, Icons.access_time, ctx),
            _buildChipOrdenacaoModal('A-Z', Ordenacao.alfabetica, Icons.sort_by_alpha, ctx),
            _buildChipOrdenacaoModal('Maior valor', Ordenacao.maiorValor, Icons.arrow_upward, ctx),
            _buildChipOrdenacaoModal('Menor valor', Ordenacao.menorValor, Icons.arrow_downward, ctx),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _buildChipOrdenacaoModal(String label, Ordenacao ordenacao, IconData icon, BuildContext ctx) {
    final isSelected = _ordenacao == ordenacao;
    return FilterChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _ordenacao = ordenacao);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _buildChipFiltroModal(String label, FiltroStatus filtro, BuildContext ctx) {
    final isSelected = _filtroStatus == filtro;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filtroStatus = filtro);
        Navigator.pop(ctx);
      },
    );
  }

  /// Abre a tela de configurações
  void _abrirConfiguracoes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConfiguracoesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos Mensais'),
        centerTitle: true,
        elevation: 2,
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtros',
              onPressed: _mostrarFiltros,
            ),
            if (_temFiltrosAtivos)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ]),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurações',
            onPressed: _abrirConfiguracoes,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Swipe para a esquerda (avança para o próximo mês)
          if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
            _proximoMes();
          }
          // Swipe para a direita (volta para o mês anterior)
          else if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            _mesAnterior();
          }
        },
        child: Column(children: [
          _buildSeletorMesAno(),
          _buildFormularioGasto(),
          const Divider(height: 1),
          if (_temFiltrosAtivos) _buildIndicadorFiltrosAtivos(),
          Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildListaGastos()),
          _buildTotalizador(),
        ]),
      ),
    );
  }

  Widget _buildIndicadorFiltrosAtivos() {
    List<String> filtrosAtivos = [];
    
    if (_filtroStatus == FiltroStatus.abertos) {
      filtrosAtivos.add('Em aberto');
    } else if (_filtroStatus == FiltroStatus.pagos) {
      filtrosAtivos.add('Pagos');
    }
    
    if (_ordenacao != Ordenacao.alfabetica) {
      filtrosAtivos.add(_textoOrdenacao);
    }
    
    final texto = filtrosAtivos.join(' • ');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(children: [
        Icon(Icons.filter_alt, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
        ),
        TextButton(
            onPressed: () => setState(() {
              _filtroStatus = FiltroStatus.todos;
              _ordenacao = Ordenacao.alfabetica;
            }),
            child: const Text('Limpar')),
      ]),
    );
  }

  Widget _buildSeletorMesAno() {
    final anos = List.generate(8, (i) => DateTime.now().year - 5 + i);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            onPressed: _mesAnterior,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Mês anterior',
            style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _mostrarSeletorMesAno(anos),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.calendar_month, size: 20),
                  const SizedBox(width: 8),
                  Text('${_nomesMeses[_mesSelecionado - 1]} $_anoSelecionado',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ]),
              ),
            ),
          ),
          IconButton(
            onPressed: _proximoMes,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Próximo mês',
            style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer),
          ),
        ]),
        if (!_isMesAtual) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _irParaMesAtual,
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Ir para mês atual'),
          ),
        ],
      ]),
    );
  }

  void _mostrarSeletorMesAno(List<int> anos) {
    int mesTmp = _mesSelecionado;
    int anoTmp = _anoSelecionado;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Selecionar Período'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: mesTmp,
                decoration:
                    const InputDecoration(labelText: 'Mês', border: OutlineInputBorder()),
                items: List.generate(
                    12, (i) => DropdownMenuItem(value: i + 1, child: Text(_nomesMeses[i]))),
                onChanged: (v) {
                  if (v != null) setStateDialog(() => mesTmp = v);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: anoTmp,
                decoration:
                    const InputDecoration(labelText: 'Ano', border: OutlineInputBorder()),
                items: anos
                    .map((a) => DropdownMenuItem(value: a, child: Text(a.toString())))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setStateDialog(() => anoTmp = v);
                },
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _mesSelecionado = mesTmp;
                      _anoSelecionado = anoTmp;
                    });
                    _salvarPreferenciasECarregar();
                  },
                  child: const Text('Confirmar')),
            ],
          );
        });
      },
    );
  }

  Widget _buildFormularioGasto() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _origemController,
                decoration: InputDecoration(
                  labelText: 'Origem (a quem devo)',
                  hintText: 'Ex: Santander, Inter',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.account_balance),
                  suffixIcon: _origensDisponiveis.isNotEmpty
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (v) => _origemController.text = v,
                          itemBuilder: (_) => _origensDisponiveis
                              .map((o) => PopupMenuItem(value: o, child: Text(o)))
                              .toList(),
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe a origem' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(
                    labelText: 'Valor',
                    hintText: '0,00',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ '),
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Informe';
                  if (CurrencyHelper.parseFromCurrency(v) <= 0) return 'Inválido';
                  return null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _adicionarGasto,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar Gasto'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ]),
      ),
    );
  }

  Widget _buildListaGastos() {
    final gastosFiltrados = _gastosFiltrados;
    if (gastosFiltrados.isEmpty) {
      String msg;
      if (_filtroStatus == FiltroStatus.abertos) {
        msg =
            'Nenhum gasto em aberto em\n${_nomesMeses[_mesSelecionado - 1]} de $_anoSelecionado';
      } else if (_filtroStatus == FiltroStatus.pagos) {
        msg =
            'Nenhum gasto pago em\n${_nomesMeses[_mesSelecionado - 1]} de $_anoSelecionado';
      } else {
        msg =
            'Nenhum gasto registrado em\n${_nomesMeses[_mesSelecionado - 1]} de $_anoSelecionado';
      }
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        ]),
      );
    }
    
    // Wrapper com indicador visual de scroll (sombras nas bordas)
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.03, 0.97, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: gastosFiltrados.length,
          itemBuilder: (_, i) => _buildGastoCard(gastosFiltrados[i]),
        ),
      ),
    );
  }

  Widget _buildGastoCard(Gasto gasto) {
    final isPago = gasto.pago;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isPago
          ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5)
          : null,
      child: InkWell(
        onLongPress: () => _editarGasto(gasto),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                isPago ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
            child: Icon(isPago ? Icons.check_circle : Icons.pending,
                color: isPago ? Colors.green : Colors.orange),
          ),
          title: Text(gasto.origem,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: isPago ? TextDecoration.lineThrough : null,
                  color: isPago ? Colors.grey : null)),
          subtitle: Text(_currencyFormat.format(gasto.valor),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: isPago ? FontWeight.normal : FontWeight.bold,
                  color: isPago ? Colors.grey : Colors.red[400],
                  decoration: isPago ? TextDecoration.lineThrough : null)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () => _editarGasto(gasto),
              tooltip: 'Editar',
            ),
            Checkbox(
                value: isPago,
                onChanged: (_) => _togglePago(gasto),
                activeColor: Colors.green),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red[400],
              onPressed: () => _confirmarExclusao(gasto),
              tooltip: 'Excluir',
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTotalizador() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Botão para expandir/minimizar
          InkWell(
            onTap: () => setState(() => _totalizadorExpandido = !_totalizadorExpandido),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  _totalizadorExpandido ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  _totalizadorExpandido ? 'Minimizar' : 'Expandir',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ]),
            ),
          ),
          // Conteúdo expansível
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _totalizadorExpandido
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_totaisPorOrigem.isNotEmpty) ...[
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _totaisPorOrigem.length,
                      itemBuilder: (_, i) {
                        final origem = _totaisPorOrigem.keys.elementAt(i);
                        final valor = _totaisPorOrigem[origem]!;
                        return Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.3)),
                          ),
                          child:
                              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(origem,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(_currencyFormat.format(valor),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[400])),
                          ]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.account_balance_wallet,
                      size: 28, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total em aberto no mês:',
                        style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                    Text(_currencyFormat.format(_totalEmAberto),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _totalEmAberto > 0 ? Colors.red[400] : Colors.green[400])),
                  ]),
                ]),
              ]),
            ),
            // Versão minimizada - apenas o total
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.account_balance_wallet,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Total: ',
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                Text(_currencyFormat.format(_totalEmAberto),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _totalEmAberto > 0 ? Colors.red[400] : Colors.green[400])),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
