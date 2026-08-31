import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/http/api_exception_l10n.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../library/data/exercise_repository.dart';
import '../../../library/domain/exercise.dart';
import '../../../library/presentation/library_screen.dart';

/// Seletor de exercício da biblioteca, aberto de dentro do builder.
///
/// Tem busca própria (e não o filtro global da tela da biblioteca): procurar
/// "supino" para montar o bloco não deve mexer no que o professor tinha
/// filtrado na aba da biblioteca.
Future<Exercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.ly.background,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _ExercisePickerSheet(),
    ),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet();

  @override
  ConsumerState<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  final _controller = TextEditingController();
  Future<ExercisePage>? _results;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    setState(() {
      _results = ref
          .read(exerciseRepositoryProvider)
          .list(filter: ExerciseFilter(query: query), limit: 40);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(LySpace.x4),
          child: LyTextField(
            label: l10n.builderPickExercise,
            hint: l10n.librarySearchHint,
            controller: _controller,
            prefixIcon: Icons.search,
            onChanged: _search,
          ),
        ),
        Expanded(
          child: FutureBuilder<ExercisePage>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(LySpace.x6),
                    child: Text(
                      describeApiError(context, snapshot.error!),
                      textAlign: TextAlign.center,
                      style: LyType.body(c.textSecondary),
                    ),
                  ),
                );
              }
              final page = snapshot.data;
              if (page == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (page.items.isEmpty) {
                return Center(
                  child: Text(
                    l10n.libraryEmpty,
                    style: LyType.body(c.textSecondary),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  LySpace.x4,
                  0,
                  LySpace.x4,
                  LySpace.x6,
                ),
                itemCount: page.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: LySpace.x2),
                itemBuilder: (context, index) {
                  final exercise = page.items[index];
                  return ExerciseTile(
                    exercise: exercise,
                    onTap: () => Navigator.of(context).pop(exercise),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
