import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final goalPromptStorageProvider = Provider<GoalPromptStorage>((ref) {
  return GoalPromptStorage();
});

/// Lembra, por usuário, que o convite "Qual é o seu objetivo?" já apareceu
/// (P5.5: sugerido uma vez após o primeiro login). Só conveniência local:
/// reinstalar o app pode mostrá-lo de novo — e ele só aparece com a anamnese
/// ainda vazia. Reusa `flutter_secure_storage`, como os rascunhos de check-in.
class GoalPromptStorage {
  GoalPromptStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static String _key(String userId) => 'lyfta.goal_prompt_shown.$userId';

  final FlutterSecureStorage _storage;

  Future<bool> wasShown(String userId) async =>
      await _storage.read(key: _key(userId)) != null;

  Future<void> markShown(String userId) =>
      _storage.write(key: _key(userId), value: '1');

  Future<void> clear(String userId) => _storage.delete(key: _key(userId));
}
