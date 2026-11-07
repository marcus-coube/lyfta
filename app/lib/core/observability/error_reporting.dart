import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';

/// Relato de crash e erro (ADR-009 §5, P4.6).
///
/// Com `SENTRY_DSN` vazio (dev e CI) nada sai do aparelho: os mesmos três
/// ganchos (zona, `FlutterError.onError`, `PlatformDispatcher.onError`) só
/// escrevem no console. Com DSN, o `sentry_flutter` instala os ganchos e
/// envia o evento já passando pelo filtro de privacidade (ADR-008): só
/// `user_id`/`tenant_id`, nunca e-mail, nome, corpo, medidas ou mensagens.
class ErrorReporting {
  const ErrorReporting._();

  /// Roda [appRunner] dentro da zona guardada e com os ganchos de erro.
  static Future<void> run(Future<void> Function() appRunner) async {
    if (AppConfig.sentryDsn.isEmpty) {
      await _runLocalOnly(appRunner);
      return;
    }
    await SentryFlutter.init(configure, appRunner: appRunner);
  }

  @visibleForTesting
  static Future<void> runLocalOnly(
    Future<void> Function() appRunner,
    void Function(Object error, StackTrace? stack) onReport,
  ) =>
      _runLocalOnly(appRunner, onReport: onReport);

  static Future<void> _runLocalOnly(
    Future<void> Function() appRunner, {
    void Function(Object error, StackTrace? stack)? onReport,
  }) async {
    void report(Object error, StackTrace? stack) {
      debugPrint('Erro não tratado: $error\n${stack ?? ''}');
      onReport?.call(error, stack);
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
    await runZonedGuarded(appRunner, report);
  }

  /// Opções do SDK. Pública para o teste conferir as travas de privacidade.
  @visibleForTesting
  static void configure(SentryFlutterOptions o) {
    o.dsn = AppConfig.sentryDsn;
    o.environment = AppConfig.sentryEnvironment;
    o.release = AppConfig.appRelease;
    o.sendDefaultPii = false;
    o.attachScreenshot = false;
    o.attachViewHierarchy = false;
    o.captureFailedRequests = false;
    // Toque em widget vira breadcrumb com rótulo/texto do botão — pode
    // conter nome de aluno ou texto digitado.
    o.enableUserInteractionBreadcrumbs = false;
    o.maxRequestBodySize = MaxRequestBodySize.never;
    o.beforeSend = (event, hint) => scrubEvent(event);
    o.beforeBreadcrumb = (crumb, hint) => scrubBreadcrumb(crumb);
  }

  /// Associa o evento ao usuário da sessão: só ids (ADR-008). `null` limpa
  /// (logout). No-op quando o relato está desligado.
  static Future<void> setSession({String? userId, String? tenantId}) async {
    if (!Sentry.isEnabled) return;
    await Sentry.configureScope((scope) async {
      if (userId == null) {
        await scope.setUser(null);
        await scope.removeTag('tenant_id');
      } else {
        await scope.setUser(SentryUser(id: userId));
        if (tenantId != null) await scope.setTag('tenant_id', tenantId);
      }
    });
  }

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final _query = RegExp(r'\?[^\s"\x27)>]*');
  static final _bearer = RegExp(r'Bearer\s+[\w.~+/=-]+', caseSensitive: false);

  /// Tira e-mail, query string e tokens de um texto livre (mensagem de
  /// exceção). Exceções de rede costumam embutir a URL completa.
  @visibleForTesting
  static String scrubText(String text) => text
      .replaceAll(_query, '')
      .replaceAll(_bearer, 'Bearer [filtrado]')
      .replaceAll(_email, '[e-mail]');

  /// Filtro de privacidade do evento (ADR-008). Mantém só `user.id`.
  @visibleForTesting
  static SentryEvent scrubEvent(SentryEvent event) {
    final user = event.user;
    if (user != null) event.user = SentryUser(id: user.id);

    final request = event.request;
    if (request != null) {
      event.request = SentryRequest(
        method: request.method,
        url: request.url == null ? null : scrubText(request.url!),
      );
    }

    final message = event.message;
    if (message != null) {
      message.formatted = scrubText(message.formatted);
      message.template = null;
      message.params = null;
    }

    for (final e in event.exceptions ?? const <SentryException>[]) {
      if (e.value != null) e.value = scrubText(e.value!);
    }
    for (final b in event.breadcrumbs ?? const <Breadcrumb>[]) {
      scrubBreadcrumb(b);
    }
    return event;
  }

  /// Breadcrumb sem query string nem headers/corpo.
  @visibleForTesting
  static Breadcrumb? scrubBreadcrumb(Breadcrumb? crumb) {
    if (crumb == null) return null;
    final data = crumb.data;
    if (data != null) {
      final clean = Map<String, dynamic>.of(data)
        ..removeWhere((k, _) => _droppedBreadcrumbKeys.contains(k));
      if (clean['url'] is String) {
        clean['url'] = scrubText(clean['url'] as String);
      }
      crumb.data = clean;
    }
    if (crumb.message != null) crumb.message = scrubText(crumb.message!);
    return crumb;
  }

  static const _droppedBreadcrumbKeys = {
    'headers',
    'request_headers',
    'query',
    'query_string',
    'http.query',
    'http.fragment',
    'body',
  };
}
