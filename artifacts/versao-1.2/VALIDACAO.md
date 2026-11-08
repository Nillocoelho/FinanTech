# Validação da versão 1.2.0

7 de novembro de 2026.

- `flutter analyze --no-pub`: nenhum erro ou aviso.
- `flutter test --no-pub`: 84 testes aprovados.
- `flutter build apk --release --no-pub`: APK gerado com sucesso, aproximadamente 56,6 MB.
- Pacote: `com.finantech.finantech`, versão `1.2.0`, código `3`, Android mínimo API 24.
- Assinatura verificada com `apksigner`; o certificado corresponde ao APK de revisão anterior.
- Migração das versões 1 e 2 do banco testada com preservação de identificadores, valores e pagamentos.
- Testes de recorrência cobrem geração sem duplicatas, exclusão de uma ocorrência, dia 31 após fevereiro, ano bissexto, edição individual, alteração de próximos lançamentos em aberto e encerramento preservando histórico e contas pagas.
- Testes de parcelamento verificam grupos independentes, conservação dos centavos, numeração, vencimentos e pagamentos.
- Backup completo testado por gravação e restauração do SQLite, incluindo regras de recorrência e seu progresso de geração.
- Fluxos de interface testados: categoria, recorrência, exclusividade entre repetição e parcelamento e consulta de parcelas.
- Capturas das telas renderizadas pelo Flutter com dados fictícios. Cenário de 360 px e texto ampliado em 1,4 validado.

O APK não foi instalado em aparelho físico nesta sessão. Notificações, permissões, compartilhamento e seleção nativa de arquivos continuam sujeitos à verificação manual no celular. A compilação emite mensagens das ferramentas Java e de dependências nativas; elas não impediram a geração do APK.
