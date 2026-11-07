import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/config/app_config.dart';
import 'package:lyfta/core/observability/error_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('sem DSN o relato fica desligado (nada é enviado)', () {
    expect(AppConfig.sentryDsn, isEmpty);
    expect(Sentry.isEnabled, isFalse);
  });

  test('setSession é no-op com o Sentry desligado', () async {
    await ErrorReporting.setSession(userId: 'u1', tenantId: 't1');
    await ErrorReporting.setSession();
  });

  test('configure trava os recursos que vazam PII', () {
    final o = SentryFlutterOptions(dsn: 'https://k@example.invalid/1');
    ErrorReporting.configure(o);
    expect(o.sendDefaultPii, isFalse);
    expect(o.attachScreenshot, isFalse);
    expect(o.attachViewHierarchy, isFalse);
    expect(o.captureFailedRequests, isFalse);
    expect(o.enableUserInteractionBreadcrumbs, isFalse);
    expect(o.maxRequestBodySize, MaxRequestBodySize.never);
    expect(o.release, AppConfig.appRelease);
  });

  group('filtro de evento (ADR-008)', () {
    test('mantém só user.id e remove e-mail, nome e IP', () {
      final event = SentryEvent(
        user: SentryUser(
          id: 'u1',
          email: 'ana@exemplo.com',
          username: 'ana',
          name: 'Ana Silva',
          ipAddress: '1.2.3.4',
        ),
        tags: {'tenant_id': 't1'},
      );
      final out = ErrorReporting.scrubEvent(event);
      expect(out.user?.id, 'u1');
      expect(out.user?.email, isNull);
      expect(out.user?.username, isNull);
      expect(out.user?.name, isNull);
      expect(out.user?.ipAddress, isNull);
      expect(out.tags?['tenant_id'], 't1');
    });

    test('request perde corpo, query, cookies e headers', () {
      final event = SentryEvent(
        request: SentryRequest(
          method: 'POST',
          url: 'https://api.test/v1/me?email=ana@exemplo.com',
          data: {'email': 'ana@exemplo.com'},
          queryString: 'email=ana@exemplo.com',
          cookies: 'sid=abc',
          headers: {'Authorization': 'Bearer abc'},
        ),
      );
      final r = ErrorReporting.scrubEvent(event).request!;
      expect(r.url, 'https://api.test/v1/me');
      expect(r.method, 'POST');
      expect(r.data, isNull);
      expect(r.queryString, isNull);
      expect(r.cookies, isNull);
      expect(r.headers, isEmpty);
    });

    test('mensagem e exceção sem e-mail, token nem query string', () {
      final event = SentryEvent(
        message: SentryMessage(
          'falhou para ana@exemplo.com',
          template: 'falhou para %s',
          params: ['ana@exemplo.com'],
        ),
        exceptions: [
          SentryException(
            type: 'DioException',
            value: 'GET https://api.test/v1/x?token=zzz Bearer abc.def falhou',
          ),
        ],
      );
      final out = ErrorReporting.scrubEvent(event);
      expect(out.message!.formatted, isNot(contains('ana@')));
      expect(out.message!.params, isNull);
      final v = out.exceptions!.single.value!;
      expect(v, isNot(contains('token=zzz')));
      expect(v, isNot(contains('abc.def')));
      expect(v, contains('https://api.test/v1/x'));
    });

    test('breadcrumb HTTP sem query string nem headers', () {
      final crumb = Breadcrumb(
        category: 'http',
        message: 'GET https://api.test/v1/x?a=1',
        data: {
          'url': 'https://api.test/v1/x?a=1',
          'headers': {'Authorization': 'Bearer abc'},
          'query': 'a=1',
          'status_code': 200,
        },
      );
      final out = ErrorReporting.scrubBreadcrumb(crumb)!;
      expect(out.data!['url'], 'https://api.test/v1/x');
      expect(out.data!.containsKey('headers'), isFalse);
      expect(out.data!.containsKey('query'), isFalse);
      expect(out.data!['status_code'], 200);
      expect(out.message, 'GET https://api.test/v1/x');
    });
  });

  test('sem DSN, erro não tratado cai na zona guardada e o app segue',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final originalOnError = FlutterError.onError;
    final originalDispatcher = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      PlatformDispatcher.instance.onError = originalDispatcher;
    });

    final reported = <Object>[];
    await ErrorReporting.runLocalOnly(
      () async {
        Future<void>.delayed(
          Duration.zero,
          () => throw StateError('assíncrono'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        FlutterError.onError!(
          FlutterErrorDetails(exception: ArgumentError('framework')),
        );
        final handled = PlatformDispatcher.instance.onError!(
          Exception('plataforma'),
          StackTrace.current,
        );
        expect(handled, isTrue);
      },
      (e, _) => reported.add(e),
    );

    expect(reported, hasLength(3));
    expect(reported.first, isA<StateError>());
  });
}
