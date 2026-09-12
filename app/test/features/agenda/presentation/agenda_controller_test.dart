import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/agenda/presentation/agenda_controller.dart';

void main() {
  group('startOfWeek', () {
    test('domingo é o próprio início da semana', () {
      // 2026-09-06 é um domingo.
      final start = startOfWeek(DateTime(2026, 9, 6, 15, 30));
      expect(start, DateTime(2026, 9, 6));
    });

    test('qualquer dia da semana volta ao domingo anterior, à meia-noite', () {
      // 2026-09-10 é uma quinta-feira; a semana (dom–sáb) começou no 6.
      final start = startOfWeek(DateTime(2026, 9, 10, 8));
      expect(start, DateTime(2026, 9, 6));
    });

    test('sábado volta ao domingo da mesma semana', () {
      // 2026-09-12 é um sábado.
      final start = startOfWeek(DateTime(2026, 9, 12));
      expect(start, DateTime(2026, 9, 6));
    });
  });
}
