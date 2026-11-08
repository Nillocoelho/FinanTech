# Registro de validação

Data: 7 de novembro de 2026. Ambiente: Windows, Flutter 3.47.9, Dart 3.13.7 e Java 21.

## Verificações

| Verificação | Resultado |
|---|---|
| Análise estática | `flutter analyze --no-pub`: nenhum erro ou aviso |
| Testes unitários, de interface e capturas | 68 testes aprovados |
| Compilação Android | `flutter build apk --release --no-pub`: APK gerado, aproximadamente 56,1 MB |
| Metadados do APK | `com.finantech.finantech`, versão 1.1.0, código 2, Android mínimo API 24, target API 36, compile API 37 |
| Capturas | Oito telas renderizadas pelo Flutter em 390 × 844 px, com fontes locais e dados de demonstração |
| Texto ampliado | Cenário de 360 px de largura com escala de texto 1,4 sem overflow detectado |

## Fluxos cobertos pelos novos testes

- Totais exibidos correspondem aos lançamentos do mês.
- Pagamento atualiza os totais e retira o aviso de atraso.
- Busca e filtros de situação funcionam juntos; limpar filtros recupera a lista.
- Estados vazio e de erro oferecem uma ação útil.
- Valor, nome e vencimento são validados antes de salvar.
- Parcelamento preserva o total e atravessa dezembro/janeiro corretamente.
- A exclusão só acontece depois da confirmação.
- A interface comporta texto ampliado no cenário testado.
- As capturas das telas continuam correspondendo à implementação.

Os testes anteriores de modelo, SQLite, backup, notificações e divisão de parcelas também permanecem na suíte.

## Limites desta validação

O APK foi compilado e teve seus metadados conferidos, mas não foi instalado nem exercitado em um aparelho físico nesta sessão. Ele utiliza a assinatura de desenvolvimento já existente no projeto e é destinado à revisão. Não representa uma publicação em loja.

Compartilhamento, seletor nativo de arquivos, permissão de notificações, restauração de backup e entrega de notificações exigem uma rodada manual em aparelho. Os serviços existentes foram preservados; os testes de interface usam um repositório em memória, sem tocar nos dados pessoais.

A compilação iOS e a leitura com TalkBack/VoiceOver não foram executadas neste ambiente. A checagem de fonte ampliada não substitui uma auditoria completa de acessibilidade. A comparação de capturas pode exigir atualização controlada ao mudar de plataforma de teste ou versão do Flutter.
