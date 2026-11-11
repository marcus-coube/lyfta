import 'package:dio/dio.dart';

import '../push/device_locale.dart';

/// Manda `Accept-Language` com o idioma que a tela está usando (P8.3), para o
/// backend resolver o conteúdo dinâmico (nome de exercício, modelos, treino do
/// dia) por ele e não pelo locale do tenant (ADR-011 §2).
///
/// O idioma é lido a cada requisição: trocar o idioma do aparelho vale na
/// próxima chamada, sem recriar o client. [localeCode] existe para teste.
class AcceptLanguageInterceptor extends Interceptor {
  AcceptLanguageInterceptor({String Function()? localeCode})
      : _localeCode =
            localeCode ?? (() => backendLocaleCode(resolveDeviceLocale()));

  final String Function() _localeCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('Accept-Language', _localeCode);
    handler.next(options);
  }
}
