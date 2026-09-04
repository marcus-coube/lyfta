import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/exercise_media.dart';
import '../domain/exercise_history.dart';

/// Seletor do exercício da aba Carga, a partir do índice `/exercises/logged`
/// (P2.1) — só aparecem exercícios que o aluno já treinou pelo menos uma
/// vez.
class ExerciseSelector extends StatelessWidget {
  const ExerciseSelector({
    required this.items,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final List<LoggedExercise> items;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    if (items.isEmpty) {
      return Text(
        l10n.evolutionNoExercisesYet,
        style: LyType.body(c.textSecondary),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: LySpace.x3),
        itemBuilder: (context, index) {
          final logged = items[index];
          final selected = logged.exercise.id == selectedId;
          return _ExerciseChip(
            logged: logged,
            selected: selected,
            onTap: () => onChanged(logged.exercise.id),
          );
        },
      ),
    );
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({
    required this.logged,
    required this.selected,
    required this.onTap,
  });

  final LoggedExercise logged;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: LyRadius.md,
        child: Container(
          width: 84,
          padding: const EdgeInsets.all(LySpace.x2),
          decoration: BoxDecoration(
            borderRadius: LyRadius.md,
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? c.accent.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            children: [
              ExerciseMedia(exercise: logged.exercise, size: 44),
              const SizedBox(height: LySpace.x1),
              Text(
                logged.exercise.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: LyType.caption(selected ? c.accent : c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
