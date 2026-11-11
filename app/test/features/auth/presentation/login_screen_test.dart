import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart'
    hide Options;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/token_storage.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/router/app_router.dart';
import 'package:lyfta/features/dashboard/data/dashboard_repository.dart';

import '../../dashboard/dashboard_fakes.dart';

/// Fake in-memory do plugin de secure storage — mesmo padrão usado em
/// `test/core/http/auth_interceptor_test.dart`.
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

/// Adapter fake do `identity`: `/v1/auth/login` aceita
/// `test@lyfta.app` / `senha-correta`, qualquer outra credencial responde
/// `401 invalid_credentials`.
class _FakeIdentityAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/v1/auth/login')) {
      final data = options.data as Map<dynamic, dynamic>;
      if (data['email'] == 'test@lyfta.app' && data['password'] == 'senha-correta') {
        return ResponseBody.fromString(
          '{"access_token":"access","refresh_token":"refresh",'
          '"tenant_id":"tenant-1","user_id":"user-1","roles":["coach"]}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        '{"code":"invalid_credentials","params":{}}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString('{}', 404);
  }
}

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: LyTheme.dark(),
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: container.read(appRouterProvider),
    ),
  );
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => AuthController(
            tokenStorage: TokenStorage(storage: const FlutterSecureStorage()),
            httpAdapter: _FakeIdentityAdapter(),
          ),
        ),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('login com credenciais corretas navega para o shell do professor', (tester) async {
    final container = buildContainer();
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('pt'));
    await tester.enterText(find.byType(TextField).at(0), 'test@lyfta.app');
    await tester.enterText(find.byType(TextField).at(1), 'senha-correta');
    await tester.tap(find.text(l10n.loginSubmit));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, l10n.homeCoachTabDashboard), findsOneWidget);
  });

  testWidgets('login com credencial errada mostra erro i18n e permanece no login', (tester) async {
    final container = buildContainer();
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'test@lyfta.app');
    await tester.enterText(find.byType(TextField).at(1), 'senha-errada');
    final l10n = lookupAppLocalizations(const Locale('pt'));
    await tester.tap(find.text(l10n.loginSubmit));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorInvalidCredentials), findsOneWidget);
    final location =
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();
    expect(location, '/login');
  });
}
