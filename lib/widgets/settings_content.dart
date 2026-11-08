import 'package:flutter/material.dart';

import '../ui/finance_theme.dart';
import '../ui/finance_widgets.dart';

class SettingsContent extends StatelessWidget {
  const SettingsContent({
    super.key,
    required this.enabled,
    required this.time,
    required this.busy,
    required this.onToggle,
    required this.onTime,
    required this.onTest,
    required this.onBackup,
    required this.onRestore,
    required this.onLocal,
    required this.onExport,
    required this.onImport,
  });
  final bool enabled, busy;
  final String time;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTime,
      onTest,
      onBackup,
      onRestore,
      onLocal,
      onExport,
      onImport;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          const Text(
            'Tudo no seu controle.',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lembretes e dados, do seu jeito.',
            style: TextStyle(color: FinanceColors.muted),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_android_outlined, color: FinanceColors.green),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seus dados ficam neste aparelho',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Guarde uma cópia do backup fora do celular para recuperar suas contas se precisar.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: FinanceColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const FinanceSection(
            title: 'Lembretes',
            subtitle: 'Um aviso antes de cada vencimento',
          ),
          _Group(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                secondary: const _SettingIcon(Icons.notifications_outlined),
                title: const Text(
                  'Avisar na véspera',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  enabled
                      ? 'Lembretes ativos às $time'
                      : 'Lembretes desativados',
                  style: const TextStyle(
                    fontSize: 12,
                    color: FinanceColors.muted,
                  ),
                ),
                value: enabled,
                onChanged: onToggle,
              ),
              _Action(
                icon: Icons.schedule_outlined,
                title: 'Horário do aviso',
                subtitle: time,
                onTap: enabled ? onTime : null,
              ),
              _Action(
                icon: Icons.notification_add_outlined,
                title: 'Enviar aviso de teste',
                subtitle: 'Confira a permissão do seu celular',
                onTap: onTest,
              ),
            ],
          ),
          const FinanceSection(
            title: 'Backup e recuperação',
            subtitle: 'Todos os meses, pagamentos e vencimentos',
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                semanticsLabel: 'Processando backup',
              ),
            ),
          _Group(
            children: [
              _Action(
                icon: Icons.cloud_upload_outlined,
                title: 'Criar e compartilhar backup',
                subtitle: 'Salve uma cópia completa em arquivo',
                onTap: busy ? null : onBackup,
              ),
              _Action(
                icon: Icons.restore_page_outlined,
                title: 'Restaurar de um arquivo',
                subtitle: 'Substitui os dados após sua confirmação',
                onTap: busy ? null : onRestore,
              ),
              _Action(
                icon: Icons.folder_outlined,
                title: 'Backups neste aparelho',
                subtitle: 'Consulte as cópias salvas localmente',
                onTap: busy ? null : onLocal,
              ),
            ],
          ),
          const FinanceSection(
            title: 'Planilhas',
            subtitle: 'Leve seus lançamentos para fora do app',
          ),
          _Group(
            children: [
              _Action(
                icon: Icons.ios_share_outlined,
                title: 'Exportar planilha',
                subtitle: 'Arquivo CSV com os valores por mês',
                onTap: busy ? null : onExport,
              ),
              _Action(
                icon: Icons.file_download_outlined,
                title: 'Importar planilha',
                subtitle: 'Adicione lançamentos de um CSV',
                onTap: busy ? null : onImport,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              'Como funciona o arquivo CSV?',
              style: TextStyle(fontSize: 12, color: FinanceColors.muted),
            ),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Text(
                  'Colunas: Origem, Abril, Maio, até Abril do ano seguinte. Os valores usam vírgula decimal e há uma linha de total no final. O CSV não substitui o backup completo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: FinanceColors.muted,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'FINANTECH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: FinanceColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Clareza para cuidar das suas contas.',
              style: TextStyle(fontSize: 12, color: FinanceColors.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: 70),
          children[i],
        ],
      ],
    ),
  );
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F3F6),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 19, color: FinanceColors.ink),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: onTap != null,
    onTap: onTap,
    leading: _SettingIcon(icon),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(
        fontSize: 12,
        height: 1.5,
        color: FinanceColors.muted,
      ),
    ),
    trailing: const Icon(Icons.chevron_right, size: 20),
  );
}
