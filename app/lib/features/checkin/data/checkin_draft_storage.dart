import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/checkin.dart';

final checkinDraftStorageProvider = Provider<CheckinDraftStorage>((ref) {
  return CheckinDraftStorage();
});

/// Rascunho local de avaliações de treino que não conseguiram sair na hora
/// (P3.5 §2). Check-in não entra na fila offline do ADR-003 (`pending_events`
/// é só execução de treino — o parâmetro é explícito no plano da tarefa):
/// isto aqui é deliberadamente mais simples, uma lista pequena que só existe
/// enquanto a rede não volta, sem `client_id`/idempotência do lado do
/// device (a idempotência de verdade já é do servidor, por
/// `session_client_id` — reenviar o mesmo rascunho depois de reconectar
/// nunca duplica).
///
/// Reusa `flutter_secure_storage` (já é dependência do `TokenStorage`) em
/// vez de trazer outro pacote de persistência só para uma lista pequena.
///
/// Uma lista por usuário: o `student_id` do check-in vem do token de quem
/// envia, então um rascunho guardado por uma conta nunca pode sair com a
/// sessão de outra que entrou depois no mesmo aparelho (E2E P4.4).
class CheckinDraftStorage {
  CheckinDraftStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'lyfta.checkin_drafts';

  static String _key(String userId) => '$_keyPrefix.$userId';

  final FlutterSecureStorage _storage;

  Future<List<CheckinDraft>> readAll(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CheckinDraft.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(String userId, CheckinDraft draft) async {
    final current = await readAll(userId);
    await _writeAll(userId, [...current, draft]);
  }

  /// Remove pelo `sessionClientId` — é a chave natural (idempotência do
  /// servidor é por ela também).
  Future<void> remove(String userId, String sessionClientId) async {
    final current = await readAll(userId);
    await _writeAll(
      userId,
      current.where((d) => d.sessionClientId != sessionClientId).toList(),
    );
  }

  /// Apaga todos os rascunhos — exclusão de conta (ADR-008 §2): nada do
  /// usuário fica no device.
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));

  Future<void> _writeAll(String userId, List<CheckinDraft> drafts) async {
    await _storage.write(
      key: _key(userId),
      value: jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
  }
}
