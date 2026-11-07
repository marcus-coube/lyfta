import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/http/api_exception.dart';
import '../data/checkin_draft_storage.dart';
import '../data/checkin_repository.dart';
import '../domain/checkin.dart';

/// O que a tela de avaliação (P3.5 §2) mostra depois de mandar.
enum CheckinSubmitOutcome {
  /// Confirmado pelo servidor na hora.
  sent,

  /// Sem rede: o rascunho ficou salvo localmente e vai sair sozinho quando
  /// reconectar (o worker abaixo cuida disso) — ADR-003 restringe a fila
  /// offline de verdade à execução de treino, então isto é deliberadamente
  /// mais simples que o `SyncWorker` do P1.7: um rascunho, não uma fila de
  /// fatos append-only.
  queuedOffline,
}

/// Envio da avaliação pós-treino + drenagem do rascunho ao reconectar
/// (P3.5 §2). Não é `autoDispose`: precisa sobreviver ao bottom sheet
/// fechar para continuar tentando em segundo plano.
class CheckinController extends Notifier<AsyncValue<void>> {
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  /// Dono dos rascunhos: o usuário logado. Trocar de conta reconstrói o
  /// controller e drena só os rascunhos da conta nova.
  String? get _userId => ref.read(authControllerProvider).userId;

  @override
  AsyncValue<void> build() {
    ref.watch(authControllerProvider.select((s) => s.userId));
    _listenConnectivity();
    ref.onDispose(() => _connectivity?.cancel());
    Future.microtask(flushDrafts);
    return const AsyncData(null);
  }

  void _listenConnectivity() {
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) unawaited(flushDrafts());
      });
    } on MissingPluginException {
      _connectivity = null;
    }
  }

  Future<CheckinSubmitOutcome> submit(CheckinDraft draft) async {
    try {
      await ref.read(checkinRepositoryProvider).create(draft);
      return CheckinSubmitOutcome.sent;
    } on ApiException catch (e) {
      final userId = _userId;
      if (e.code != 'network_error' || userId == null) rethrow;
      await ref.read(checkinDraftStorageProvider).add(userId, draft);
      return CheckinSubmitOutcome.queuedOffline;
    }
  }

  /// Tenta mandar os rascunhos guardados — chamado na volta da rede e no
  /// boot do provider (um rascunho pode ter ficado de uma sessão anterior
  /// do app fechada ainda offline).
  Future<void> flushDrafts() async {
    final userId = _userId;
    if (userId == null) return;
    final storage = ref.read(checkinDraftStorageProvider);
    final repo = ref.read(checkinRepositoryProvider);
    final drafts = await storage.readAll(userId);
    for (final draft in drafts) {
      try {
        await repo.create(draft);
        await storage.remove(userId, draft.sessionClientId);
      } on ApiException catch (e) {
        if (e.code == 'network_error') return; // ainda sem rede, tenta depois
        // Erro de conteúdo (não deveria acontecer — a tela já validou):
        // reenviar para sempre não adianta, mas manter o rascunho preso
        // também não. Remove para não travar o resto da fila.
        await storage.remove(userId, draft.sessionClientId);
      }
    }
  }
}

final checkinControllerProvider =
    NotifierProvider<CheckinController, AsyncValue<void>>(
  CheckinController.new,
);
