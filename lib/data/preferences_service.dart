import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciar as preferências do usuário usando SharedPreferences.
/// 
/// Persiste configurações como o último mês/ano selecionado para que o app
/// lembre da escolha do usuário ao reabrir.
class PreferencesService {
  static const String _keyMesSelecionado = 'mes_selecionado';
  static const String _keyAnoSelecionado = 'ano_selecionado';

  /// Salva o mês e ano selecionados
  Future<void> salvarMesAnoSelecionado(int mes, int ano) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMesSelecionado, mes);
    await prefs.setInt(_keyAnoSelecionado, ano);
  }

  /// Recupera o mês selecionado salvo, ou retorna o mês atual se não houver
  Future<int> getMesSelecionado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMesSelecionado) ?? DateTime.now().month;
  }

  /// Recupera o ano selecionado salvo, ou retorna o ano atual se não houver
  Future<int> getAnoSelecionado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAnoSelecionado) ?? DateTime.now().year;
  }

  /// Recupera mês e ano selecionados de uma vez
  Future<({int mes, int ano})> getMesAnoSelecionado() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();
    final mes = prefs.getInt(_keyMesSelecionado) ?? agora.month;
    final ano = prefs.getInt(_keyAnoSelecionado) ?? agora.year;
    return (mes: mes, ano: ano);
  }

  /// Limpa as preferências salvas (volta para os valores padrão)
  Future<void> limparPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMesSelecionado);
    await prefs.remove(_keyAnoSelecionado);
  }
}
