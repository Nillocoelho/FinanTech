import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:finantech/models/gasto.dart';
import 'package:finantech/services/backup_service.dart';

void main() {
  final original = Gasto(id: 1, origem: 'Cartão', valor: 125.50,
      pago: true, mes: 11, ano: 2026, createdAt: '2026-11-03T09:00:00',
      vencimento: DateTime(2026, 11, 20));

  test('backup preserves IDs, amounts, paid status and due dates', () {
    final restored = BackupService.decode(BackupService.encode([original]));
    expect(restored.single.toMap(), original.toMap());
  });

  test('empty backups are valid', () {
    expect(BackupService.decode(BackupService.encode([])), isEmpty);
  });

  test('rejects unsupported files and versions', () {
    for (final content in ['not json', '[]', '{}',
      '{"app":"FinanTech","version":2,"gastos":[]}']) {
      expect(() => BackupService.decode(content), throwsFormatException);
    }
  });

  test('rejects corrupt records before restoration', () {
    for (final change in <Map<String, dynamic>>[
      {'valor': -1}, {'valor': '100'}, {'mes': 13}, {'pago': 2},
      {'vencimento': 'invalid'}, {'createdAt': null}, {'id': null},
      {'origem': ''},
    ]) {
      final row = {...original.toMap(), ...change};
      final content = jsonEncode({'app': 'FinanTech', 'version': 1, 'gastos': [row]});
      expect(() => BackupService.decode(content), throwsFormatException);
    }
  });

  test('rejects duplicate IDs instead of overwriting a record', () {
    expect(() => BackupService.decode(BackupService.encode([original, original])),
        throwsFormatException);
  });
}
