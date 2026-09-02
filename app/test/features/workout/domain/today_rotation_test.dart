import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/workout/domain/today.dart';

/// Payload mínimo de `/v1/me/today` com o rodízio (P1.8).
Map<String, dynamic> _payload({
  required List<String> labels,
  String? todayLabel,
  String? nextLabel,
}) {
  final rotation = [
    for (var i = 0; i < labels.length; i++)
      {
        'id': 'day-${labels[i]}',
        'label': labels[i],
        'position': i,
        'title': 'Treino ${labels[i]}',
      },
  ];
  return {
    'status': todayLabel == null ? 'rest_day' : 'ready',
    'plan': {'id': 'p1', 'title': 'Plano', 'version_id': 'v1', 'version_no': 1},
    'day': todayLabel == null
        ? null
        : {'id': 'day-$todayLabel', 'label': todayLabel, 'title': '', 'blocks': <Map<String, dynamic>>[]},
    'rotation': rotation,
    'next_day_id': nextLabel == null ? null : 'day-$nextLabel',
    'previous_loads': <Map<String, dynamic>>[],
    'recent_sessions': <Map<String, dynamic>>[],
  };
}

void main() {
  test('a rotação chega em ordem e o próximo treino é resolvido pelo id', () {
    final today = Today.fromJson(
      _payload(labels: ['A', 'B', 'C'], todayLabel: 'A', nextLabel: 'B'),
    );

    expect(today.rotation.map((d) => d.label), ['A', 'B', 'C']);
    expect(today.rotation.map((d) => d.position), [0, 1, 2]);
    expect(today.nextDay?.label, 'B');
  });

  test('quem calcula o próximo é o servidor, não a ordem da lista', () {
    // Depois de um override para o C, o servidor promete o A — a tela tem de
    // seguir o `next_day_id`, não "o de baixo na lista".
    final today = Today.fromJson(
      _payload(labels: ['A', 'B', 'C'], todayLabel: 'C', nextLabel: 'A'),
    );

    expect(today.nextDay?.label, 'A');
  });

  test('rodízio de um dia só não anuncia próximo treino', () {
    final today = Today.fromJson(
      _payload(labels: ['A'], todayLabel: 'A', nextLabel: 'A'),
    );

    // Repetir o rótulo de hoje como "próximo" seria ruído, não informação.
    expect(today.nextDay, isNull);
  });

  test('dia de descanso continua com o rodízio para trocar o treino', () {
    final today = Today.fromJson(
      _payload(labels: ['A', 'B'], nextLabel: 'A'),
    );

    expect(today.status, TodayStatus.restDay);
    expect(today.rotation, hasLength(2));
    expect(today.nextDay?.label, 'A');
  });

  test('payload sem rotação (servidor antigo) não quebra a tela', () {
    final today = Today.fromJson({
      'status': 'rest_day',
      'previous_loads': <Map<String, dynamic>>[],
      'recent_sessions': <Map<String, dynamic>>[],
    });

    expect(today.rotation, isEmpty);
    expect(today.nextDay, isNull);
  });

  test('a rotação sobrevive ao cache local, que guarda o JSON cru', () {
    final raw = jsonEncode(
      _payload(labels: ['A', 'B', 'C'], todayLabel: 'B', nextLabel: 'C'),
    );

    final today = Today.decode(raw);

    expect(today.rotation.map((d) => d.label), ['A', 'B', 'C']);
    expect(today.nextDay?.label, 'C');
    expect(today.rotation.first.title, 'Treino A');
  });
}
