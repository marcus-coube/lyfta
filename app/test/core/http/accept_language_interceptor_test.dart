import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/http/accept_language_interceptor.dart';

void main() {
  test('manda Accept-Language com o idioma da tela a cada chamada', () async {
    var code = 'en';
    final seen = <String?>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..interceptors.addAll([
        AcceptLanguageInterceptor(localeCode: () => code),
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seen.add(options.headers['Accept-Language'] as String?);
            handler.resolve(Response(requestOptions: options, statusCode: 200));
          },
        ),
      ]);

    await dio.get<void>('/x');
    code = 'pt-PT';
    await dio.get<void>('/x');
    await dio.get<void>(
      '/x',
      options: Options(headers: {'Accept-Language': 'pt-BR'}),
    );

    expect(seen, ['en', 'pt-PT', 'pt-BR']);
  });
}
