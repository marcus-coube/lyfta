import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/http/api_exception.dart';
import 'workout_repository.dart';

/// O que a barra do app mostra sobre a sincronização: quantos fatos ainda
/// não chegaram ao servidor e se o último despacho falhou.
class SyncState {
  const SyncState({
    this.pending = 0,
    this.syncing = false,
    this.failed = false,
    this.drainedRevision = 0,
  });

  final int pending;
  final bool syncing;

  /// Última tentativa falhou por rede — a fila continua intacta e o worker
  /// já reagendou.
  final bool failed;

  /// Sobe a cada drenagem que **de fato** despachou eventos.
  ///
  /// É o gatilho de "o servidor sabe de coisas novas": ao chegar o
  /// `session_finish`, a rotação avança lá (ADR-004 §3) e o treino do dia
  /// que está na tela vira passado. Sem isso o aluno voltaria do modo avião
  /// e continuaria vendo — e podendo repetir — o treino que acabou de fazer.
  final int drainedRevision;

  bool get hasPending => pending > 0;

  SyncState copyWith({
    int? pending,
    bool? syncing,
    bool? failed,
    int? drainedRevision,
  }) {
    return SyncState(
      pending: pending ?? this.pending,
      syncing: syncing ?? this.syncing,
      failed: failed ?? this.failed,
      drainedRevision: drainedRevision ?? this.drainedRevision,
    );
  }
}

final syncWorkerProvider = NotifierProvider<SyncWorker, SyncState>(
  SyncWorker.new,
);

/// Worker que drena a fila offline (ADR-003 §4).
///
/// Três gatilhos: cada evento novo enfileirado, a volta da conectividade
/// (`connectivity_plus`) e o backoff exponencial depois de uma falha. Nunca
/// bloqueia a UI — o aluno registra série e segue treinando.
class SyncWorker extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;

  /// Teto do backoff: meia hora sem rede não deve virar espera de horas — o
  /// aluno sai do ginásio e o celular reencontra o Wi-Fi.
  static const Duration _maxBackoff = Duration(minutes: 5);

  @override
  SyncState build() {
    _listenConnectivity();
    ref.onDispose(() {
      _connectivity?.cancel();
      _retry?.cancel();
    });
    // Um aluno que fechou o app com a fila cheia precisa ver isso ao abrir.
    Future.microtask(refreshPending);
    return const SyncState();
  }

  String? get _studentId => ref.read(authControllerProvider).userId;

  void _listenConnectivity() {
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) unawaited(sync());
      });
    } on MissingPluginException {
      // Plataforma sem o plugin (ex.: teste de widget): o app continua
      // funcionando, só perde o gatilho de reconexão.
      _connectivity = null;
    }
  }

  Future<void> refreshPending() async {
    final studentId = _studentId;
    if (studentId == null) return;
    final pending =
        await ref.read(workoutRepositoryProvider).pendingCount(studentId);
    state = state.copyWith(pending: pending);
  }

  /// Drena a fila até esvaziar. Chamadas concorrentes são ignoradas: o
  /// mesmo lote saindo duas vezes seria idempotente no servidor, mas gastar
  /// rede do aluno à toa não.
  Future<void> sync() async {
    final studentId = _studentId;
    if (studentId == null || _running) return;
    _running = true;
    final repo = ref.read(workoutRepositoryProvider);

    // Tudo que mexe em `state` fica dentro do try/finally: uma exceção antes
    // dele deixaria `_running` travado em true e o worker nunca mais
    // drenaria a fila.
    try {
      _retry?.cancel();
      state = state.copyWith(syncing: true);
      var sent = 0;
      while (true) {
        final drained = await repo.drainOnce(studentId);
        if (drained == 0) break;
        sent += drained;
      }
      _attempt = 0;
      state = SyncState(
        pending: await repo.pendingCount(studentId),
        drainedRevision:
            sent > 0 ? state.drainedRevision + 1 : state.drainedRevision,
      );
    } on ApiException {
      state = state.copyWith(
        syncing: false,
        failed: true,
        pending: await repo.pendingCount(studentId),
      );
      _scheduleRetry();
    } finally {
      _running = false;
    }
  }

  /// Backoff exponencial (2s, 4s, 8s… até [_maxBackoff]).
  void _scheduleRetry() {
    _attempt++;
    final seconds = 1 << (_attempt.clamp(1, 8));
    final delay = Duration(seconds: seconds) < _maxBackoff
        ? Duration(seconds: seconds)
        : _maxBackoff;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(sync()));
  }
}
