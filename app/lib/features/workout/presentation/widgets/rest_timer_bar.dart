import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../rest_timer_controller.dart';

/// Barra do descanso entre séries, fixa no rodapé do player.
///
/// Fica sempre visível enquanto conta: o aluno larga o celular e volta a
/// olhar — a informação não pode depender de onde a lista está rolada.
class RestTimerBar extends ConsumerWidget {
  const RestTimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final rest = ref.watch(restTimerProvider);
    if (rest == null) return const SizedBox.shrink();

    final over = rest.isOver;

    return Material(
      color: over ? c.accent : c.surfaceElevated,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(LySpace.x4),
          child: Row(
            children: [
              Text(
                _clock(rest.remaining),
                style: LyType.numeric(
                  over ? c.onAccent : c.textPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: LySpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      over ? l10n.sessionRestOver : l10n.sessionRestTitle,
                      style: LyType.label(over ? c.onAccent : c.textPrimary),
                    ),
                    Text(
                      rest.label,
                      style: LyType.caption(
                        over ? c.onAccent : c.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: ref.read(restTimerProvider.notifier).stop,
                child: Text(l10n.sessionRestSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `m:ss` — a leitura de relógio que o aluno espera de um cronômetro.
  String _clock(Duration remaining) {
    final total = remaining.inSeconds.clamp(0, 359999);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
