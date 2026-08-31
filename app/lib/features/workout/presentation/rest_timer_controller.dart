import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rest_timer_service.dart';

/// Descanso em andamento entre duas séries.
class RestState {
  const RestState({required this.total, required this.remaining, required this.label});

  final Duration total;
  final Duration remaining;

  /// Nome do exercício da série que acabou — o aluno olha o celular no meio
  /// do descanso e precisa saber de que série é a contagem.
  final String label;

  bool get isOver => remaining <= Duration.zero;

  double get progress => total.inSeconds == 0
      ? 1
      : 1 - (remaining.inSeconds / total.inSeconds).clamp(0, 1);
}

final restTimerProvider = NotifierProvider<RestTimerController, RestState?>(
  RestTimerController.new,
);

/// Contagem regressiva do descanso.
///
/// O relógio da tela é só a metade visível: quem garante o aviso com o app
/// em segundo plano é a notificação agendada em [RestTimerService], porque
/// um `Timer` do Dart não sobrevive ao sistema suspender o app.
class RestTimerController extends Notifier<RestState?> {
  Timer? _ticker;

  @override
  RestState? build() {
    ref.onDispose(_cancelTicker);
    return null;
  }

  void start({
    required Duration rest,
    required String label,
    required String notificationTitle,
    required String notificationBody,
  }) {
    _cancelTicker();
    if (rest <= Duration.zero) {
      state = null;
      return;
    }
    state = RestState(total: rest, remaining: rest, label: label);
    unawaited(
      ref.read(restTimerServiceProvider).schedule(
            rest: rest,
            title: notificationTitle,
            body: notificationBody,
          ),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final current = state;
    if (current == null) {
      _cancelTicker();
      return;
    }
    final remaining = current.remaining - const Duration(seconds: 1);
    if (remaining <= Duration.zero) {
      _cancelTicker();
      state = RestState(total: current.total, remaining: Duration.zero, label: current.label);
      unawaited(ref.read(restTimerServiceProvider).alertNow());
      return;
    }
    state = RestState(total: current.total, remaining: remaining, label: current.label);
  }

  /// Pular o descanso cancela também a notificação: o aluno já voltou para a
  /// barra, um aviso 40 s depois só assusta.
  void stop() {
    _cancelTicker();
    state = null;
    unawaited(ref.read(restTimerServiceProvider).cancel());
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
