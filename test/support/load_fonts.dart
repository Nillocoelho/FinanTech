import 'package:flutter/services.dart';

Future<void> loadFinanceFonts() async {
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
  }
  await loader.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
