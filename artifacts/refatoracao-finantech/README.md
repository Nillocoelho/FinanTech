# FinanTech — refatoração da experiência mobile

**Entrega de revisão · 7 de novembro de 2026**

Abra `index.html` para percorrer as oito capturas reais do Flutter. A implementação está no projeto; o pacote inclui o código completo em `source-code.zip`, um patch aplicável sobre o commit `ec53798` e um APK para teste. Os valores e nomes das capturas são fictícios, definidos exclusivamente nos testes. O aplicativo instalado continua usando os dados locais de cada pessoa.

## Direção de produto

Tema claro e sóbrio, azul profundo e verde pontual, conforme a preferência escolhida. O aplicativo passa a se apresentar como uma ferramenta de controle de contas: valores legíveis, ações previsíveis e atenção ao vencimento. A identidade usa tipografia e espaçamento, sem gráficos decorativos, saldos inventados, gradientes ou promessas de sincronização.

O produto acompanha despesas. Por isso, o destaque é **A pagar no mês**, e não saldo disponível, patrimônio ou receita. A barra representa a proporção do valor mensal já pago, com esse significado escrito ao lado.

## Telas e fluxos implementados

| Área | Refatoração | Comportamento |
|---|---|---|
| Visão geral | Resumo de valor a pagar, total do mês e valor pago; aviso de atraso; contas ordenadas por vencimento | Totais calculados a partir do mês inteiro. O aviso abre diretamente as contas vencidas. A prévia mostra até cinco contas. |
| Lançamentos | Lista com valores à direita, nome e status à esquerda, busca e filtros | Busca combina com Todas, Em aberto, Pagas e Vencidas. Ordenação por vencimento, nome, valor e criação. |
| Novo lançamento | Folha inferior com valor, nome, vencimento e parcelamento | Validação antes de salvar. Sugestões de nomes existentes. Mostra estimativa de parcelas e explica a soma de nomes duplicados no mês. |
| Edição | Mesma estrutura visual do formulário de criação | Mantém identificador, mês de referência e situação de pagamento. Valida conflito de nome no mês. |
| Resumo mensal | Totais e distribuição por origem com valores explícitos | Inclui valores pagos e em aberto; as barras representam a participação de cada origem no total. |
| Ajustes | Grupos de lembretes, backup e planilhas | Horário, aviso de teste, criação/restauração de backup, cópias locais e CSV continuam conectados aos serviços existentes. |

### Navegação

- Barra inferior: Visão geral, Lançamentos e Ajustes.
- Botão **+**, na barra superior: adicionar gasto, acessível por tooltip e sem cobrir linhas da lista.
- Seleção de mês e ano, setas de navegação e retorno ao mês atual.
- Toque na conta abre a edição. O menu de três pontos oferece pagamento, edição e exclusão.
- Exclusão exige confirmação. Restauração de backup continua explicando a substituição dos dados e criando uma cópia de segurança.
- Arrastar para baixo atualiza os dados do mês.

## Sistema visual

| Token | Valor | Uso |
|---|---|---|
| Azul profundo | `#142B45` | Valores, títulos, ação principal e cartão de resumo |
| Fundo | `#F4F6F8` | Superfície do aplicativo |
| Superfície | `#FFFFFF` | Campos e grupos de conteúdo |
| Texto secundário | `#64748B` | Descrições e metadados |
| Divisórias | `#E3E8EF` | Limites discretos e separação de linhas |
| Verde | `#087F5B` | Pagamentos concluídos |
| Vermelho | `#B42332` | Vencimento ultrapassado e exclusão |
| Tipografia | Roboto 400, 500 e 700, incluída no projeto | Renderização consistente sem buscar fontes pela internet |
| Tipografia numérica | Algarismos tabulares | Comparação dos valores nas listas e no resumo |
| Escala | 11–14 px para metadados; 17–28 px para títulos; 34 px para o valor principal | Hierarquia financeira |
| Espaçamento | Base de 4 px; margens de 20–24 px | Ritmo e alinhamento |
| Cantos | 12 px em campos, 16 px em cartões e 24 px em folhas | Consistência entre telas |

Ícones acompanham ações ou informações. Estados são escritos por extenso, como **Pago**, **Em aberto** e **Vencido**; a cor complementa a informação. Campos e botões seguem os componentes Material para foco, teclado e semântica. Datas, calendário e diálogos usam português do Brasil.

## Estados e regras de informação

- **Sem dados:** convite para adicionar a primeira conta, sem métricas fictícias.
- **Busca sem resultados:** explica o resultado e oferece limpar filtros.
- **Carregando:** indicador de progresso sem apresentar zeros como se fossem dados carregados.
- **Falha de leitura:** mensagem e ação para tentar novamente.
- **Gravação:** indicador e bloqueio da ação principal enquanto a operação está em andamento.
- **Atraso:** considera o dia local; uma conta que vence hoje ainda não é vencida.
- **Parcelas:** preservam os centavos do valor total, atravessam o ano e ajustam o dia ao último dia válido de cada mês. O primeiro lançamento continua pertencendo ao mês selecionado.
- **Dados:** SQLite, migração, modelo e serviços de backup permanecem na camada existente. Não há integração bancária, login ou armazenamento em nuvem nesta entrega.

## Estrutura da implementação

| Arquivo | Responsabilidade |
|---|---|
| `lib/ui/finance_theme.dart` | Cores, tipografia e estilos Material |
| `lib/ui/finance_widgets.dart` | Resumo mensal, linha de conta, título de seção e estado vazio |
| `lib/widgets/expense_editor.dart` | Formulário compartilhado e validação de lançamento |
| `lib/widgets/settings_content.dart` | Apresentação e agrupamento de ajustes |
| `lib/pages/gastos_page.dart` | Carregamento, filtros, navegação e operações sobre as contas |
| `lib/pages/configuracoes_page.dart` | Integração dos ajustes com os serviços existentes |
| `lib/main.dart` | Tema e localização pt-BR |
| `test/support/` | Repositório de demonstração e carregamento de fontes, exclusivos de teste |

A tela anterior de gastos tinha aproximadamente 1.900 linhas. A composição visual agora usa componentes compartilhados, e as operações de armazenamento continuam no repositório. Leituras têm controle de geração para impedir que uma resposta antiga substitua um mês selecionado mais recentemente.

## Revisão e reprodução

1. Abra `index.html` e percorra as telas.
2. Instale o APK de revisão em um aparelho Android de teste. O build usa a assinatura de desenvolvimento já configurada no projeto.
3. Verifique valores, vencimentos, busca, pagamento, edição e parcelamento com seus próprios dados de teste.
4. Confira o registro de validação em `VALIDACAO.md`.

Para reproduzir as capturas, na raiz do projeto:

```sh
flutter pub get
flutter test --update-goldens test/refactor_preview_test.dart
flutter analyze
flutter test
flutter build apk --release
```

As capturas têm viewport de 390 × 844 px e não incluem a barra de status do sistema. Não houve teste manual em aparelho físico nem compilação iOS neste ambiente Windows. O teste com fonte ampliada cobre um cenário de layout; ele não equivale a uma auditoria completa com TalkBack ou VoiceOver.

O patch é gerado com os novos arquivos e as fontes incluídos. Em um checkout limpo do commit base, use `git apply --check refatoracao.patch` antes de aplicar com `git apply refatoracao.patch`.
