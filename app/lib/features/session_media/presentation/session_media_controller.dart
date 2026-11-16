import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session_media_repository.dart';
import '../domain/session_media.dart';

/// Envio em andamento (ou que falhou e espera "tentar de novo").
class MediaUpload {
  const MediaUpload({
    required this.media,
    this.note,
    this.exerciseId,
    this.exerciseName,
    this.progress = 0,
    this.error,
  });

  final PreparedMedia media;
  final String? note;
  final String? exerciseId;
  final String? exerciseName;
  final double progress;
  final Object? error;

  bool get failed => error != null;

  MediaUpload copyWith({double? progress, Object? error, bool clearError = false}) {
    return MediaUpload(
      media: media,
      note: note,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SessionMediaState {
  const SessionMediaState({this.items = const [], this.upload});

  /// O que o servidor já tem desta sessão.
  final List<SessionMedia> items;
  final MediaUpload? upload;

  bool get uploading => upload != null && !upload!.failed;

  /// O servidor conta linhas (inclusive expiradas) e o envio em curso.
  bool get atLimit =>
      items.length + (upload != null ? 1 : 0) >= sessionMediaMaxPerSession;
}

/// Mídia de execução de uma sessão (chave = `session.clientId`).
///
/// O envio roda aqui, fora de qualquer tela: fechar a folha ou continuar
/// registrando séries não interrompe nem espera o upload (P12.2 §4). Não há
/// fila persistente — exige rede e vale enquanto a sessão está aberta
/// (ADR-020, fora do ADR-003).
class SessionMediaController
    extends FamilyNotifier<SessionMediaState, String> {
  CancelToken? _cancel;
  bool _disposed = false;

  @override
  SessionMediaState build(String arg) {
    ref.onDispose(() {
      _disposed = true;
      _cancel?.cancel();
    });
    Future.microtask(refresh);
    return const SessionMediaState();
  }

  /// Recarrega a lista do servidor; offline, mantém o que já tinha.
  Future<void> refresh() async {
    try {
      final items = await ref.read(sessionMediaRepositoryProvider).list(arg);
      if (_disposed) return;
      state = SessionMediaState(items: items, upload: state.upload);
    } catch (_) {
      // Sem rede a lista simplesmente não atualiza.
    }
  }

  /// Dispara o envio sem esperar: devolve o `Future` só para teste/aguardo.
  Future<void> start({
    required PreparedMedia media,
    String? note,
    String? exerciseId,
    String? exerciseName,
  }) {
    if (state.uploading) return Future.value();
    return _run(
      MediaUpload(
        media: media,
        note: note,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
      ),
    );
  }

  Future<void> retry() {
    final current = state.upload;
    if (current == null || !current.failed) return Future.value();
    return _run(current.copyWith(progress: 0, clearError: true));
  }

  /// Cancela o que está subindo ou descarta o que falhou.
  void cancel() {
    final current = state.upload;
    if (current == null) return;
    if (current.failed) {
      state = SessionMediaState(items: state.items);
    } else {
      _cancel?.cancel();
    }
  }

  Future<void> remove(String id) async {
    await ref.read(sessionMediaRepositoryProvider).delete(id);
    if (_disposed) return;
    state = SessionMediaState(
      items: [
        for (final m in state.items)
          if (m.id != id) m,
      ],
      upload: state.upload,
    );
  }

  Future<void> _run(MediaUpload upload) async {
    final token = _cancel = CancelToken();
    state = SessionMediaState(items: state.items, upload: upload);
    try {
      final created = await ref.read(sessionMediaRepositoryProvider).upload(
            sessionClientId: arg,
            media: upload.media,
            exerciseId: upload.exerciseId,
            exerciseName: upload.exerciseName,
            note: upload.note,
            cancelToken: token,
            onProgress: (p) {
              if (_disposed || !identical(_cancel, token)) return;
              final current = state.upload;
              if (current == null) return;
              state = SessionMediaState(
                items: state.items,
                upload: current.copyWith(progress: p),
              );
            },
          );
      if (_disposed) return;
      state = SessionMediaState(items: [...state.items, created]);
    } on DioException catch (e) {
      if (_disposed) return;
      if (CancelToken.isCancel(e)) {
        state = SessionMediaState(items: state.items);
        return;
      }
      _fail(upload, e);
    } catch (e) {
      if (_disposed) return;
      _fail(upload, e);
    }
  }

  void _fail(MediaUpload upload, Object error) {
    state = SessionMediaState(
      items: state.items,
      upload: upload.copyWith(error: error),
    );
  }
}

final sessionMediaProvider = NotifierProvider.family<SessionMediaController,
    SessionMediaState, String>(SessionMediaController.new);
