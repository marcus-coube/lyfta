# ADR-021 — Marca DÜO Training (substitui Lyfta)

**Status:** Aceito (pedido do PO, 2026-11-16)
**Data:** 2026-11-16

## Contexto

O PO trocou o nome do produto de Lyfta para **DÜO Training** ("Simples de
seguir. Fácil de confiar."). A identidade nova mantém o visual escuro e
verde-limão do app, para a troca de nome não exigir redesenhar as telas. Ninguém
usa o app e nada subiu em loja (ADR-015): é o momento barato de trocar também
os identificadores técnicos.

## Decisão

1. **Nome de exibição:** `DÜO` (com trema) em UI, textos legais, e-mails e
   docs; "DÜO Training" quando couber o nome completo. Em português o nome é
   masculino ("o DÜO", "do DÜO").
2. **Identificadores técnicos:** `duo`, sem trema — pacote Dart `duo`, módulos
   Go `github.com/marcus-coube/duo/<serviço>`, bancos `duo_<serviço>`, role
   `duo_app`, bucket `duo-media`, chaves de armazenamento local `duo.*`,
   canais de notificação `duo_*`, esquema de deep link `duo://`.
3. **Android:** `applicationId`/namespace `br.com.duotraining.duo` (ainda
   provisório, ADR-015). O projeto Firebase **continua** `lyfta-a3bd3` (ID de
   projeto não muda); o app Android precisa ser registrado de novo lá com o
   package novo antes de baixar o `google-services.json` (L1).
4. **Domínio placeholder:** `duotraining.app` (`privacidade@`, `no-reply@`,
   `media.`, `app.`) até o domínio real ser registrado.
5. **Identidade visual** (fonte de verdade: `app/lib/core/design_system/`):
   - Paleta: fundo `#0B0D0F`, superfície elevada `#1F2327`, destaque único
     verde-limão `#C8F135`, texto `#F2F4F0`.
   - Tipografia: Manrope 800 nos títulos, 400 no texto; JetBrains Mono nos
     rótulos pequenos (`LyType.caption`/`LyType.mono`).
   - Marca: letreiro "DÜO" com o Ü em verde-limão e pontos quadrados;
     ícone do app = Ü escuro sobre quadrado verde-limão (`LyLogo`,
     `LyAppIcon`, `ic_launcher`).
6. **Termos:** os textos legais mudam o nome do controlador → `TERMS_VERSION`
   `2026-11-v4` (todos reaceitam no próximo login).
7. **Fica como está:** o prefixo `Ly*` dos componentes do design system
   (legado, sem efeito para o usuário), o nome do repositório/pasta e o
   histórico do git.

## Consequências

- Bancos novos (`create-dbs.sql` cria `duo_*`); os `lyfta_*` locais ficam
  órfãos e podem ser apagados à mão. `.env` de cada máquina precisa trocar
  `lyfta` por `duo` (DATABASE_URL, bucket, MAIL_FROM).
- Sessões salvas no app (chaves `lyfta.*`) se perdem: todo mundo entra de novo.
- O compose sobe como projeto `duo`: derrubar os contêineres antigos com
  `docker compose -p lyfta down` antes do `up`.
