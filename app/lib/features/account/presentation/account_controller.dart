import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../checkin/data/checkin_draft_storage.dart';
import '../../workout/data/workout_repository.dart';
import '../data/account_repository.dart';

/// Estado de consentimento exibido na tela Conta (`GET /v1/me/consents`).
final consentStatusProvider = FutureProvider.autoDispose<ConsentStatus>((ref) {
  return ref.watch(accountRepositoryProvider).consents();
});

/// Telefone e nascimento do próprio usuário (`GET /v1/me`).
final myProfileProvider = FutureProvider.autoDispose<MyProfile>((ref) {
  return ref.watch(accountRepositoryProvider).profile();
});

/// Liga/desliga uma finalidade opcional (hoje, `progress_photos`) e aplica o
/// token novo, para a mudança valer nos outros serviços sem esperar o access
/// token antigo expirar.
Future<void> setConsent(
  WidgetRef ref,
  String purpose, {
  required bool granted,
}) async {
  final status =
      await ref.read(accountRepositoryProvider).putConsents({purpose: granted});
  await ref.read(authControllerProvider.notifier).applyConsentResult(
        accessToken: status.accessToken,
        needsConsent: status.needsConsent,
      );
  ref.invalidate(consentStatusProvider);
}

/// Exclusão de conta (ADR-008 §2): o servidor apaga/anonimiza em todos os
/// serviços; só depois limpamos o device — banco local do treino, rascunhos de
/// check-in e sessão — e o router leva ao login. Se o servidor falhar, nada
/// local é apagado e o usuário pode tentar de novo.
Future<void> deleteAccount(WidgetRef ref, String password) async {
  final userId = ref.read(authControllerProvider).userId;
  await ref.read(accountRepositoryProvider).deleteMe(password);
  await ref.read(workoutRepositoryProvider).clearLocal();
  if (userId != null) {
    await ref.read(checkinDraftStorageProvider).clear(userId);
  }
  await ref.read(authControllerProvider.notifier).completeAccountDeletion();
}
