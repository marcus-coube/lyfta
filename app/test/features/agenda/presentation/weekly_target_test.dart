import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/agenda/presentation/agenda_controller.dart';

void main() {
  group('resolveWeeklyTarget', () {
    test('a meta da anamnese vale mesmo com rodízio maior', () {
      expect(resolveWeeklyTarget(profileTarget: 2, rotationLength: 3), 2);
    });

    test('sem meta, usa o tamanho do rodízio', () {
      expect(resolveWeeklyTarget(rotationLength: 3), 3);
    });

    test('sem meta e sem rodízio, 1', () {
      expect(resolveWeeklyTarget(rotationLength: 0), 1);
    });
  });
}
