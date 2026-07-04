import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart'
    hide Options;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/http/auth_interceptor.dart';
import 'package:lyfta/core/http/token_storage.dart';

/// Fake in-memory do plugin de secure storage, para testar [TokenStorage]
/// sem depender de platform channels.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async =>
      Map.of(_values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _values.clear();
}

/// Adapter fake: `/protected` sempre devolve 401 na 1ª chamada por token, e
/// 200 se o header `Authorization` contiver "new-access". `/refresh` conta
/// quantas vezes foi chamado.
class _FakeAdapter implements HttpClientAdapter {
  int refreshCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/refresh')) {
      refreshCalls++;
      // Pequeno atraso para permitir que requisições concorrentes cheguem
      // enquanto o refresh está em voo (exercita a fila).
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return ResponseBody.fromString(
        '{"access_token":"new-access","refresh_token":"new-refresh"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final auth = options.headers['Authorization'] as String?;
    if (auth == 'Bearer new-access') {
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '{"code":"unauthenticated"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late TokenStorage tokenStorage;
  late Dio dio;
  late _FakeAdapter adapter;
  late bool sessionExpired;

  setUp(() async {
    tokenStorage = TokenStorage(
      storage: const FlutterSecureStorage(aOptions: AndroidOptions()),
    );
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    await tokenStorage.save(
      const AuthTokens(accessToken: 'old-access', refreshToken: 'old-refresh'),
    );

    adapter = _FakeAdapter();
    sessionExpired = false;

    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        tokenStorage: tokenStorage,
        onSessionExpired: () => sessionExpired = true,
        refreshTokens: (refreshToken) async {
          final response = await dio.post<Map<String, dynamic>>(
            '/refresh',
            data: {'refresh_token': refreshToken},
            options: Options(extra: {'skipAuth': true}),
          );
          final data = response.data!;
          return AuthTokens(
            accessToken: data['access_token'] as String,
            refreshToken: data['refresh_token'] as String,
          );
        },
      ),
    );
  });

  test('401 dispara refresh e reenvia a requisição original com o novo access token', () async {
    final response = await dio.get<Map<String, dynamic>>('/protected');

    expect(response.statusCode, 200);
    expect(response.data, {'ok': true});
    expect(adapter.refreshCalls, 1);
    expect(sessionExpired, isFalse);

    final saved = await tokenStorage.read();
    expect(saved!.accessToken, 'new-access');
  });

  test('requisições concorrentes com 401 compartilham um único refresh', () async {
    final results = await Future.wait([
      dio.get<Map<String, dynamic>>('/protected'),
      dio.get<Map<String, dynamic>>('/protected'),
      dio.get<Map<String, dynamic>>('/protected'),
    ]);

    for (final response in results) {
      expect(response.statusCode, 200);
    }
    expect(adapter.refreshCalls, 1);
  });
}
