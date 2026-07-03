# 005 - Design System

Implementado em código: `app/lib/core/design_system/` (barrel `design_system.dart`).
Regras de uso: `docs/guidelines/flutter.md`.

## Identidade

- **Voz**: atlética, direta, alto contraste. Dark é o tema de assinatura; light existe para o contexto web/administrativo.
- **Cor**: grafite profundo (escala *ink*) + um único destaque — **Lyfta Lime `#C8F135`**. Sem segunda cor de marca; semânticas (success/warning/danger/info) só para estado.
- **Tipografia**: Manrope. Títulos w700–800 com tracking negativo; corpo w500. Números de treino (carga/séries/timer) com algarismos tabulares (`LyType.numeric`).
- **Forma**: cantos suaves (inputs/botões 12, cards 16), sombras discretas; no dark, elevação = cor de superfície, não sombra. CTA primário pode ter glow lime.
- **Logo**: símbolo "anilha" (3 traços ink sobre quadrado lime arredondado) + wordmark `lyfta` minúsculo (`LyLogo`).

## Temas

Light e Dark (`LyTheme.light()` / `LyTheme.dark()`), tokens via `ThemeExtension` → `context.ly`.

## Tokens

| Grupo | Arquivo | Resumo |
|---|---|---|
| Colors | `tokens/ly_colors.dart` | `LyPalette` (bruta) + `LyColors` (resolvida por tema) |
| Typography | `tokens/ly_typography.dart` | display 32 → caption 11, Manrope |
| Spacing | `tokens/ly_spacing.dart` | escala de 4px (`x1`–`x16`) |
| Radius | `tokens/ly_radius.dart` | sm 8 / md 12 / lg 16 / xl 24 / pill |
| Elevation | `tokens/ly_elevation.dart` | none/low/medium + accentGlow |
| Motion | `tokens/ly_motion.dart` | 120/200/320ms, easeOutCubic |

## Componentes

Prontos: `LyButton` (primary/secondary/ghost, loading), `LyTextField` (label + toggle senha), `LyCard`, `LyLogo`.

Planejados: Charts, Dialogs, WorkoutCard, ExerciseTile, RestTimer.
