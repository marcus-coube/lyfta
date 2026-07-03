# Guidelines — Flutter (app + web)

Complementa `001-arquitetura.md`, `006-mobile.md`, `007-web.md` e ADR-003/005/011.

## Estrutura (feature-first)

```
app/lib/
  core/
    design_system/     # tokens + tema + componentes Ly* (só importar o barrel)
    network/ storage/ router/  # (futuro)
  shared/              # widgets/utils usados por 2+ features
  features/
    <feature>/
      domain/          # entidades, repositórios (interfaces), casos de uso
      data/            # DTOs, API/SQLite datasources, repositórios (impl)
      presentation/    # screens, widgets, controllers/providers
```

- Feature não importa outra feature; o que for comum sobe para `shared/` ou `core/`.
- Widget não conhece API/SQLite — só controller/provider → caso de uso → repositório.

## Design system (obrigatório)

- **Zero hardcode** de cor, fonte, raio, sombra ou espaçamento em feature. Só tokens: `context.ly.*`, `LyType.*`, `LySpace.*`, `LyRadius.*`, `LyMotion.*`.
- Componentes novos e reutilizáveis nascem em `core/design_system/components/` com prefixo `Ly`; um uso só = fica na feature.
- Um CTA `LyButton primary` por tela; dark é o tema de assinatura, light precisa continuar funcional.
- Mudou token ou componente → confere as duas plataformas (mobile e web) e os dois temas.

## Estado & navegação

- Estado: Riverpod (providers por feature; nada de estado global solto).
- Navegação: `go_router` com rotas nomeadas e deep links (`006-mobile.md`).
- Responsividade: breakpoints `<600` mobile, `600–1023` tablet, `>=1024` desktop. Web é desktop-first (`007-web.md`); nada de layout separado por plataforma — mesmo widget, `LayoutBuilder`.

## Offline & dados (ADR-003)

- SQLite via `drift` como fonte de verdade local para execução de treino; API sincroniza por trás (repositório decide, widget não sabe).
- Toda escrita offline gera operação pendente idempotente (client id + updated_at).

## i18n & acessibilidade

- Strings sempre em `.arb` (`intl`), pt-BR default (ADR-011). Nunca string literal em widget.
- Touch targets ≥ 44px, contraste AA (lime sobre ink passa; nunca lime sobre branco em texto), `Semantics` em componentes do DS.

## Qualidade

- `flutter_lints` + regras do `analysis_options.yaml`; `flutter analyze` limpo no CI.
- Teste de widget para todo componente do DS; golden tests quando o visual estabilizar.
- `const` sempre que possível; sem lógica de negócio em `build()`.
