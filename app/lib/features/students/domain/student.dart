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
    this.coachId,
    this.coachName,
    this.phone,
    this.birthDate,
    this.pendingInvitation,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      coachId: json['coach_id'] as String?,
      coachName: json['coach_name'] as String?,
      phone: json['phone'] as String?,
      birthDate: _parseDay(json['birth_date'] as String?),
      pendingInvitation: json['pending_invitation'] == null
          ? null
          : PendingInvitation.fromJson(
              json['pending_invitation'] as Map<String, dynamic>,
            ),
    );
  }

  /// `yyyy-MM-dd` do servidor como dia civil (sem fuso).
  static DateTime? _parseDay(String? raw) {
    if (raw == null || raw.length < 10) return null;
    final y = int.tryParse(raw.substring(0, 4));
    final m = int.tryParse(raw.substring(5, 7));
    final d = int.tryParse(raw.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  final String id;
  final String name;
  final String email;

  /// `invited` enquanto o aluno não aceitou o convite: ainda dá para montar
  /// plano, ele só não consegue entrar.
  final String status;

  /// Professor vinculado ao aluno (ADR-016). O identity devolve ao coach só os
  /// alunos dele; o nome só é exibido ao owner, que vê todos.
  final String? coachId;
  final String? coachName;

  /// Só a ficha (`GET /v1/students/{id}`) traz telefone, nascimento e convite;
  /// a lista não.
  final String? phone;
  final DateTime? birthDate;
  final PendingInvitation? pendingInvitation;

  bool get isPending => status == 'invited';
  bool get isInactive => status == 'inactive';
}

/// Convite ainda não aceito do aluno (ficha), com o que o app precisa para
/// oferecer o reenvio.
class PendingInvitation {
  const PendingInvitation({required this.id, required this.expired});

  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    return PendingInvitation(
      id: json['id'] as String,
      expired: json['expired'] as bool? ?? false,
    );
  }

  final String id;
  final bool expired;
}

/// Filtro de status da lista de alunos. O padrão é [active]: o servidor
/// esconde os inativos quando nenhum status é pedido, mas o filtro explícito
/// também tira os convites pendentes da vista "Ativos".
enum StudentStatusFilter {
  active('active'),
  inactive('inactive'),
  invited('invited');

  const StudentStatusFilter(this.apiValue);

  final String apiValue;
}

/// Uma mudança de status do aluno (`GET /v1/students/{id}/status-history`).
class StatusEvent {
  const StatusEvent({
    required this.from,
    required this.to,
    required this.changedByName,
    required this.createdAt,
    this.reason,
  });

  factory StatusEvent.fromJson(Map<String, dynamic> json) {
    return StatusEvent(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      changedByName: json['changed_by_name'] as String? ?? '',
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String from;
  final String to;
  final String changedByName;
  final String? reason;
  final DateTime createdAt;
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

/// Um professor que pode receber alunos: usuário ativo com papel coach ou
/// owner (ADR-016 §2) — as opções do "Trocar professor".
class CoachOption {
  const CoachOption({required this.id, required this.name});

  factory CoachOption.fromJson(Map<String, dynamic> json) {
    return CoachOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
    );
  }

  final String id;
  final String name;
}
