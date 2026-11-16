import 'package:flutter_test/flutter_test.dart';
import 'package:duo/shared/domain/plan.dart';

void main() {
  test('cluster, rótulo, variação e tempo fazem o round-trip do rascunho', () {
    final block = Block.fromJson({
      'block_type': 'cluster',
      'rest_seconds': 20,
      'exercises': [
        {
          'exercise_id': 'e1',
          'sets': [
            {
              'reps_min': 5,
              'label': 'Aquecimento',
              'tempo': '3-1-1-0',
              'variation': {'id': 'v1', 'name': 'Pausa', 'description': 'd'},
            },
            {'reps_min': 5},
          ],
        },
      ],
    });

    expect(block.blockType, BlockType.cluster);
    expect(block.blockType.isRounds, isFalse);

    final json = block.toJson();
    final sets = (json['exercises'] as List).single['sets'] as List;
    expect(json['block_type'], 'cluster');
    expect(sets[0]['label'], 'Aquecimento');
    expect(sets[0]['variation_id'], 'v1');
    expect(sets[0]['tempo'], '3-1-1-0');
    expect(sets[0].containsKey('variation'), isFalse);
    expect(sets[1]['label'], isNull);
    expect(sets[1]['variation_id'], isNull);
    expect(sets[1].containsKey('tempo'), isFalse);
  });

  test('copy preserva variação e tempo; keepLabel:false solta só o rótulo', () {
    final set = PrescribedSet(
      label: 'Top set',
      tempo: '2-0-1-0',
      variation: const SetVariation(id: 'v', name: 'n'),
    );
    final copy = set.copy(keepLabel: false);
    expect(copy.label, isNull);
    expect(copy.variation?.id, 'v');
    expect(copy.tempo, '2-0-1-0');
    expect(set.copy().label, 'Top set');
  });
}
