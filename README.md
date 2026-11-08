# 💰 FinanTech - Controle de Gastos Mensais

<p align="center">
  <img src="assets/images/icon.png" alt="FinanTech Logo" width="120"/>
</p>

<p align="center">
  <strong>Tenha o controle total das suas finanças pessoais na palma da mão!</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white" alt="SQLite"/>
</p>

---

## 📖 Sobre o Projeto

O **FinanTech** é um aplicativo mobile desenvolvido em Flutter para gerenciamento de gastos mensais. Com uma interface moderna e intuitiva em tema escuro, você pode registrar, acompanhar e organizar todas as suas despesas de forma simples e eficiente.

Todos os dados ficam armazenados localmente no seu dispositivo usando SQLite, garantindo privacidade e funcionamento offline.

---

## ✨ Funcionalidades

| Funcionalidade | Descrição |
|----------------|-----------|
| 📝 **Registrar Gastos** | Adicione despesas informando origem, valor e descrição |
| 📅 **Visualização Mensal** | Navegue entre meses/anos com setas intuitivas |
| ✅ **Marcar como Pago** | Controle quais contas já foram quitadas |
| 🗑️ **Exclusão com Confirmação** | Evite exclusões acidentais com diálogo de confirmação |
| ✏️ **Editar Gastos** | Modifique informações de gastos já cadastrados |
| 🔍 **Filtros Avançados** | Filtre por status (aberto/pago) e ordene por diferentes critérios |
| 💵 **Máscara de Moeda** | Formatação automática em Real (R$) |
| 📊 **Totalizador Inteligente** | Veja o resumo do mês com total geral e por status |
| 🔔 **Notificações** | Avisos na véspera do vencimento, com horário configurável |
| **Backup completo** | Crie, compartilhe e restaure os gastos de todos os meses |
| 🎨 **Tema Escuro** | Interface moderna e confortável para os olhos |
| 📱 **100% Offline** | Funciona sem internet, dados salvos localmente |

---

## 📸 Screenshots

> *Em breve...*

---

## 🛠️ Tecnologias Utilizadas

- **[Flutter](https://flutter.dev/)** - Framework UI multiplataforma
- **[Dart](https://dart.dev/)** - Linguagem de programação
- **[SQLite (sqflite)](https://pub.dev/packages/sqflite)** - Banco de dados local
- **[SharedPreferences](https://pub.dev/packages/shared_preferences)** - Persistência de preferências
- **[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)** - Notificações locais
- **[intl](https://pub.dev/packages/intl)** - Formatação de valores monetários

---

## 📁 Estrutura do Projeto

```
lib/
├── main.dart                        # Ponto de entrada do app
├── data/
│   ├── database_helper.dart         # Gerenciador de conexão SQLite
│   ├── gastos_repository.dart       # Operações CRUD de gastos
│   └── preferences_service.dart     # Serviço de preferências
├── models/
│   └── gasto.dart                   # Modelo de dados Gasto
├── pages/
│   ├── gastos_page.dart             # Tela principal do app
│   └── configuracoes_page.dart      # Tela de configurações
├── services/
│   └── notification_service.dart    # Serviço de notificações
└── utils/
    └── currency_helper.dart         # Utilitários de formatação monetária
```

---

## 🗄️ Estrutura do Banco de Dados

### Tabela: `gastos`

| Coluna     | Tipo    | Descrição                          |
|------------|---------|-------------------------------------|
| id         | INTEGER | Chave primária, auto-incremento    |
| origem     | TEXT    | A quem você deve (ex: "Santander") |
| valor      | REAL    | Valor da dívida                    |
| pago       | INTEGER | 0 = não pago, 1 = pago             |
| mes        | INTEGER | Mês do gasto (1-12)                |
| ano        | INTEGER | Ano do gasto (ex: 2025)            |
| createdAt  | TEXT    | Data de criação (ISO8601)          |

---

## 🚀 Como Executar

### Pré-requisitos

- Flutter SDK 3.47+ e Dart 3.13+
- Java 21, Android SDK Platform 37 e Build Tools 36.0.0
- iOS 14+ para executar no iPhone
- Android Studio ou VS Code com extensões Flutter/Dart
- Emulador Android ou dispositivo físico

### Instalação

```bash
# Clone o repositório
git clone https://github.com/Nillocoelho/FinanTech.git

# Entre na pasta do projeto
cd FinanTech

# Instale as dependências
flutter pub get

# Execute o app
flutter run
```

### Validar a atualização

```bash
flutter analyze
flutter test
flutter pub outdated
```

No Windows, ative o Modo de Desenvolvedor para permitir os links simbólicos usados pelos plugins Flutter.
As dependências indiretas podem permanecer em versões fixadas pelo Flutter ou pelos próprios plugins; não use overrides para forçar versões incompatíveis.

### Gerar APK

```bash
flutter build apk --release
```

O APK será gerado em: `build/app/outputs/flutter-apk/app-release.apk`

---

## 📖 Como Usar

1. **📅 Navegue pelo mês**: Use as setas `<` `>` para mudar de mês
2. **➕ Adicione um gasto**: Preencha origem, valor e clique em "Adicionar"
3. **✅ Marque como pago**: Toque no checkbox para quitar a despesa
4. **✏️ Edite**: Toque no gasto para abrir o modo de edição
5. **🗑️ Exclua**: Use o ícone de lixeira (com confirmação)
6. **🔍 Filtre**: Acesse o ícone de filtro no AppBar para ordenar e filtrar
7. **⚙️ Configure**: Acesse as configurações para ativar notificações

---

## 💡 Dicas

- O **totalizador** no rodapé pode ser minimizado tocando na seta
- Ao digitar uma origem já existente, o app sugere o **autocomplete**
- Os **cards de origem** são clicáveis e mostram o total daquela categoria
- O app **valida duplicatas** antes de adicionar novos gastos

---

## 🧪 Testes

O projeto inclui testes unitários para garantir a qualidade do código:

```bash
flutter test
```

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou pull requests.

---

## 📄 Licença

Este projeto é de uso livre para fins educacionais e pessoais.

---

<p align="center">
  Feito com ❤️ usando Flutter
</p>
