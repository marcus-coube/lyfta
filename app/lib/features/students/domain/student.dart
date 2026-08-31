/// Um usuário do tenant, como o `identity` devolve em `GET /v1/users`.
///
/// A lista de alunos vem do `identity` porque o vínculo aluno↔tenant vive
/// lá — o `workout` guarda o plano, mas não sabe quem é aluno de quem
/// (ADR-013 §2).
class Student {
  const Student({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
    );
  }

  final String id;
  final String name;
  final String email;

  /// `invited` enquanto o aluno não aceitou o convite: ainda dá para montar
  /// plano, ele só não consegue entrar.
  final String status;

  bool get isPending => status == 'invited';
}

/// Uma página da lista de alunos.
class StudentPage {
  const StudentPage({required this.items, this.nextCursor});

  factory StudentPage.fromJson(Map<String, dynamic> json) {
    final cursor = json['next_cursor'] as String?;
    return StudentPage(
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((raw) => Student.fromJson(raw as Map<String, dynamic>))
          .toList(),
      nextCursor: (cursor ?? '').isEmpty ? null : cursor,
    );
  }

  final List<Student> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
