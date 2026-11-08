# FinanTech 1.2.0

## Novidades

- Categorias no cadastro e na edição, filtro por categoria e distribuição mensal dos gastos por categoria.
- Repetição mensal para aluguel, assinaturas e outras contas fixas. O aplicativo gera as ocorrências ao abrir e mantém uma previsão de 12 meses a partir do período atual ou selecionado.
- Edição de apenas uma ocorrência ou das próximas em aberto a partir do mês escolhido, preservando os pagamentos já registrados.
- Encerramento da repetição pelo menu da conta. Remove os meses posteriores em aberto; mantém o mês selecionado, o histórico e as contas pagas.
- Novos parcelamentos guardam o grupo da compra, o número e o total de parcelas. O menu **Ver parcelamento** apresenta as parcelas pagas, as que estão em aberto e o valor ainda pendente.
- **Próximos meses**, ao final da visão geral, soma as parcelas e contas recorrentes ainda em aberto nos três meses seguintes. Lançamentos avulsos não entram nessa previsão específica.
- O backup JSON completo agora preserva categorias, parcelas e regras de recorrência; continua lendo os backups da versão anterior.

## Atualização dos dados existentes

O banco migra automaticamente das versões 1 e 2 para a versão 3, preservando identificadores, valores, pagamentos e vencimentos. Contas antigas recebem **Sem categoria** e podem ser classificadas na edição.

Os parcelamentos criados anteriormente não possuíam identificadores de compra nem numeração. Eles permanecem cadastrados, sem tentar deduzir vínculos que poderiam estar incorretos. O acompanhamento de grupos vale para os novos parcelamentos.

Lançamentos avulsos do mesmo nome e categoria no mês continuam somando os valores. Compras parceladas e recorrências são independentes e não se misturam por nome.

As recorrências são atualizadas ao abrir ou navegar no aplicativo. Não há serviço de geração mensal em segundo plano. As ocorrências já geradas usam os lembretes locais existentes, sujeitos às permissões e limitações do celular.

O CSV mantém o formato anterior de planilha. Para preservar todos os novos dados e vínculos, use o backup JSON completo.

## Capturas

As imagens em `previews/` são renderizadas pelo Flutter com dados fictícios, exclusivos dos testes. Não representam os dados pessoais de quem instala o aplicativo.

## APK

O APK da versão 1.2.0, código 3, é gerado a partir do código desta atualização. Usa a configuração de assinatura de desenvolvimento já existente no projeto. A validação em aparelho físico, incluindo permissões de notificação e compartilhamento nativo de arquivos, deve ser feita no celular.
