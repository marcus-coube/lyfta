import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/workout/domain/set_input.dart';

void main() {
  group('SetInput.parse', () {
    test('vazio é válido e vira nulo (não informado)', () {
      final input = SetInput.parse(reps: ' ', load: '');
      expect(input.isValid, isTrue);
      expect(input.reps, isNull);
      expect(input.load, isNull);
    });

    test('aceita vírgula decimal e os limites exatos do servidor', () {
      final input = SetInput.parse(reps: '1000', load: '1000,0');
      expect(input.isValid, isTrue);
      expect(input.reps, 1000);
      expect(input.load, 1000);
      expect(SetInput.parse(reps: '0', load: '47.5').load, 47.5);
    });

    test('acima do limite é inválido (A9)', () {
      final input = SetInput.parse(reps: '1001', load: '1000,5');
      expect(input.repsInvalid, isTrue);
      expect(input.loadInvalid, isTrue);
      expect(input.isValid, isFalse);
    });

    test('texto que não vira número é inválido, não nulo silencioso', () {
      final input = SetInput.parse(reps: '10', load: '5.2,5');
      expect(input.repsInvalid, isFalse);
      expect(input.loadInvalid, isTrue);
    });
  });
}
