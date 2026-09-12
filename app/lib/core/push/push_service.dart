import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'device_locale.dart';
import 'push_deep_link.dart';
import 'push_repository.dart';

/// FCM do app (P3.4 servidor + P3.5 §4 cliente): permissão, registro do
/// token em `POST /v1/devices`, exibição em primeiro plano e o deep link de
/// quem tocou a notificação.
///
/// **Só mobile** — `firebase_messaging` não tem contraparte de push no
/// navegador que valha a pena para o MVP; web fica com o badge in-app da
/// aba Chat (`unreadTotalProvider`), que já é a verdade sem depender de
/// notificação nenhuma (ADR-012 §2 empurra web push para o 3.0, anotado
/// também no plano da fase). O guard usa `defaultTargetPlatform`
/// (`package:flutter/foundation.dart`), o mesmo do `RestTimerService`
/// (P1.7) — evita importar `dart:io`, que não compila para web.
class PushService {
  PushService({required PushRepository repository, FirebaseMessaging? messaging})
      : _repository = repository,
        _messaging = messaging;

  final PushRepository _repository;
  FirebaseMessaging? _messaging;
  final _localPlugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'lyfta_push';
  static const int _foregroundNotificationId = 2001;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  bool _localNotificationsReady = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  FirebaseMessaging get _instance => _messaging ??= FirebaseMessaging.instance;

  /// Chamado uma vez, no boot do app (mobile) — liga os três fios: exibição
  /// em primeiro plano, deep link de quem toca a notificação com o app já
  /// aberto/em segundo plano, e o deep link de quem abriu o app **pela**
  /// notificação (cold start, `getInitialMessage`).
  Future<void> init({required ValueChanged<PushDeepLink> onDeepLink}) async {
    if (!isSupported) return;
    try {
      _foregroundSub = FirebaseMessaging.onMessage.listen(_showForeground);
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => onDeepLink(PushDeepLink.fromData(message.data)),
      );
      final initial = await _instance.getInitialMessage();
      if (initial != null) onDeepLink(PushDeepLink.fromData(initial.data));
    } catch (_) {
      // Sem Firebase configurado neste device (ex.: `google-services.json`
      // ainda não versionado — ver app/README.md § Firebase), push é
      // conforto, não requisito: o resto do app segue funcionando.
    }
  }

  /// Pede permissão, pega o token do FCM e registra em `POST /v1/devices`
  /// (P3.4) — chamado no sign-in e sempre que a sessão autentica de novo no
  /// boot. Também assina `onTokenRefresh`: o FCM pode trocar o token a
  /// qualquer momento (reinstalação, troca de conta no Google Play
  /// Services), e um token velho registrado nunca mais recebe nada.
  Future<void> ensureRegistered() async {
    if (!isSupported) return;
    try {
      await _instance.requestPermission();
      final token = await _instance.getToken();
      if (token != null) await _registerToken(token);
      unawaited(_tokenRefreshSub?.cancel());
      _tokenRefreshSub = _instance.onTokenRefresh.listen(_registerToken);
    } catch (_) {
      // Idem: sem credencial/config de Firebase, só loga por baixo — não
      // pode travar o boot da sessão.
    }
  }

  Future<void> _registerToken(String token) async {
    final locale = backendLocaleCode(resolveDeviceLocale());
    final platform = defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';
    try {
      await _repository.registerDevice(
        platform: platform,
        token: token,
        locale: locale,
      );
    } catch (_) {
      // Falha de rede no registro não é fatal — a próxima sessão tenta de
      // novo (não há fila offline para isto, mesmo critério do check-in de
      // dor leve: não é a execução de treino do ADR-003).
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _ensureLocalNotificationsReady();
      await _localPlugin.show(
        id: _foregroundNotificationId,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Lyfta',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (_) {
      // Notificação em primeiro plano é conforto — o app já está aberto, o
      // badge da aba Chat (WS) é a fonte de verdade de qualquer forma.
    }
  }

  Future<void> _ensureLocalNotificationsReady() async {
    if (_localNotificationsReady) return;
    await _localPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _localNotificationsReady = true;
  }

  void dispose() {
    unawaited(_tokenRefreshSub?.cancel());
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedAppSub?.cancel());
  }
}
