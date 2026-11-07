import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/providers.dart';

/// Nome (ou e-mail, se o convite ainda não tiver nome) de cada usuário do
/// tenant, por id — o `comms` só guarda ids (ADR-013 §2: nenhum serviço lê o
/// banco do outro), então "quem é o outro participante" de uma conversa só
/// o `identity` sabe (`GET /v1/users`, P1.6).
///
/// Uma chamada por papel (coach/owner e aluno) em vez de uma por conversa —
/// mesmo motivo do `StudentsController` (P1.6) evitar N+1, só que aqui nem
/// paginado: até [_pageLimit] de cada papel cobre qualquer tenant do MVP;
/// tenant maior que isso é uma dívida a paginar quando doer (mesmo critério
/// da nota de execução do P1.6).
final participantDirectoryProvider = FutureProvider<Map<String, String>>((ref) async {
  const pageLimit = 200;
  final dio = ref.watch(identityApiClientProvider).dio;

  // Cada papel falha sozinho: o aluno só pode ler a equipe (coach/owner) e
  // recebe 403 na lista de alunos — sem isso, um 403 apagava o diretório
  // inteiro e o chat do aluno ficava sem o nome do professor (E2E P4.4).
  Future<Map<String, dynamic>?> fetchRole(String role) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/v1/users',
        queryParameters: {'role': role, 'limit': pageLimit},
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return null;
      rethrow;
    }
  }

  final responses = await Future.wait([
    fetchRole('student'),
    fetchRole('coach'),
    fetchRole('owner'),
  ]);

  final directory = <String, String>{};
  for (final response in responses) {
    final items = response?['items'] as List<dynamic>? ?? const [];
    for (final raw in items) {
      final user = raw as Map<String, dynamic>;
      final id = user['id'] as String;
      final name = user['name'] as String? ?? '';
      final email = user['email'] as String? ?? '';
      directory[id] = name.isNotEmpty ? name : email;
    }
  }
  return directory;
});
