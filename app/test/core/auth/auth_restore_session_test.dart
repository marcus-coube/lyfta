import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart'
    hide Options;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/http/token_storage.dart';

/// Fake in-memory do plugin de secure storage — mesmo padrão dos outros
/// testes de auth.
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
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(_values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _values.clear();
}

/// Adapter que simula o `identity` inalcançável — o que o device vê em modo
/// avião.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'sem rede',
    );
  }
}

/// Adapter que recusa o refresh: token revogado ou expirado.
class _RejectingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"code":"invalid_token","params":{}}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late TokenStorage storage;

  setUp(() async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    storage = TokenStorage(storage: const FlutterSecureStorage());
    await storage.saveSession(
      const StoredSession(
        tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
        tenantId: 'tenant-1',
        userId: 'user-1',
        roles: {'student'},
      ),
    );
  });

  Future<AuthState> restoreWith(HttpClientAdapter adapter) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => AuthController(tokenStorage: storage, httpAdapter: adapter),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    // O restore é assíncrono: espera sair de `unknown`.
    while (container.read(authControllerProvider).status ==
        AuthStatus.unknown) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(authControllerProvider);
  }

  test('sem rede a sessão guardada continua valendo', () async {
    // O aluno que abre o app em modo avião tem de cair no treino baixado, não
    // no login: sem rede ele nem conseguiria entrar de novo, e a fila de
    // execução ficaria presa atrás da tela de login (ADR-003 §1).
    final state = await restoreWith(_OfflineAdapter());

    expect(state.isAuthenticated, isTrue);
    expect(state.userId, 'user-1');
    expect(state.tenantId, 'tenant-1');
    expect(state.roles, {UserRole.student});
    expect(
      await storage.readSession(),
      isNotNull,
      reason: 'falha de rede não pode apagar a sessão do device',
    );
  });

  test('refresh recusado pelo servidor desloga e limpa a sessão', () async {
    // O outro lado da moeda: token revogado é resposta do servidor, não
    // ausência dele — aí deslogar é o certo.
    final state = await restoreWith(_RejectingAdapter());

    expect(state.isAuthenticated, isFalse);
    expect(await storage.readSession(), isNull);
  });
}
