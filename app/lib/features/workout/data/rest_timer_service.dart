import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';

final restTimerServiceProvider = Provider<RestTimerService>((ref) {
  final service = RestTimerService();
  ref.onDispose(service.cancel);
  return service;
});

/// O alarme do descanso entre séries.
///
/// São dois mecanismos para o mesmo aviso, porque cobrem situações
/// diferentes: **em primeiro plano** o app vibra e toca o som do sistema no
/// instante certo; **com o app fechado ou em segundo plano** — que é o caso
/// normal, o aluno guarda o celular no bolso entre as séries — quem avisa é
/// a notificação local agendada.
///
/// Na web só o primeiro mecanismo existe: `flutter_local_notifications` não
/// tem implementação para navegador, e o aluno com a aba aberta recebe o
/// aviso em primeiro plano de qualquer forma.
class RestTimerService {
  RestTimerService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Id fixo: só existe um descanso por vez, e agendar outro substitui o
  /// anterior em vez de empilhar avisos velhos.
  static const int _notificationId = 1001;
  static const String _channelId = 'lyfta_rest_timer';

  bool get _supportsNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _ensureReady() async {
    if (_ready || !_supportsNotifications) return;
    tz.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    _ready = true;
  }

  /// Agenda o aviso de fim de descanso. [title] e [body] chegam já
  /// traduzidos: serviço não conhece `AppLocalizations` (ADR-011).
  Future<void> schedule({
    required Duration rest,
    required String title,
    required String body,
  }) async {
    if (!_supportsNotifications || rest <= Duration.zero) return;
    try {
      await _ensureReady();
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          title,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      );
      final when = tz.TZDateTime.now(tz.local).add(rest);
      try {
        await _plugin.zonedSchedule(
          id: _notificationId,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } on PlatformException {
        // Android 12+ pode negar alarme exato (SCHEDULE_EXACT_ALARM). Um
        // descanso avisado com alguns segundos de atraso é muito melhor que
        // descanso sem aviso nenhum.
        await _plugin.zonedSchedule(
          id: _notificationId,
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Notificação é conforto, não requisito: sem permissão, o timer da
      // tela continua contando e avisando em primeiro plano.
    }
  }

  /// Cancela o aviso agendado — série refeita, descanso pulado ou treino
  /// encerrado antes da hora.
  Future<void> cancel() async {
    if (!_supportsNotifications || !_ready) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (_) {
      // Idem: cancelar aviso que não existe não é problema do aluno.
    }
  }

  /// Dispara o aviso de primeiro plano: vibração + som do sistema.
  Future<void> alertNow() async {
    unawaited(SystemSound.play(SystemSoundType.alert));
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 600);
      }
    } catch (_) {
      // Plataforma sem vibração (web/desktop): o som já avisou.
    }
  }
}
