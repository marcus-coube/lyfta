import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duo/core/l10n/gen/app_localizations.dart';
import 'package:duo/features/workout/presentation/prescription_format.dart';
import 'package:duo/shared/domain/plan.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));

  test('carga-alvo sem unidade é kg (o builder grava assim)', () {
    final label = prescriptionLabel(
      l10n,
      PrescribedSet(repsMin: 8, repsMax: 12, targetLoadKg: 20),
    );
    expect(label, endsWith('· 20 kg'));
  });

  test('alvo relativo usa target_value e a unidade', () {
    final label = prescriptionLabel(
      l10n,
      PrescribedSet(
        repsMin: 8,
        repsMax: 10,
        targetUnit: TargetUnit.rpe,
        targetValue: 8,
      ),
    );
    expect(label, contains('8'));
    expect(label, isNot(contains('kg')));
  });

  test('sem alvo mostra só as repetições', () {
    final label =
        prescriptionLabel(l10n, PrescribedSet(repsMin: 8, repsMax: 12));
    expect(label, isNot(contains('·')));
  });
}
