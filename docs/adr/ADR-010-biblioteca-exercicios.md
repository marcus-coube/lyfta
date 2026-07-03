# ADR-010 — Biblioteca de exercícios: base aberta + curadoria própria

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

Workout builder e muscle map dependem de uma biblioteca de exercícios com nome,
mídia (GIF/vídeo), instruções e mapeamento de músculos. Produzir do zero é inviável;
licenciar base comercial tem custo recorrente.

## Decisão

1. **Semear a partir de bases abertas** com licença permissiva — candidatas:
   `free-exercise-db` (licença aberta, ~800 exercícios com imagens) e dados do projeto
   wger (verificar licença item a item antes de importar; **registrar a origem e a
   licença de cada mídia** em `exercise_media.source_license`).
2. **Curadoria própria em cima da base:** tradução pt-BR/pt-PT (ver ADR-011),
   revisão de nomes conforme uso brasileiro, e mapeamento exercício→músculo com
   percentual de esforço (`exercise_muscles (exercise_id, muscle_id, effort_pct, role: primary|secondary)`)
   — este mapeamento é o insumo do muscle map e é curado manualmente.
3. **Dois níveis de biblioteca:**
   - **Global (Lyfta):** somente leitura para tenants, mantida por nós.
   - **Do tenant:** coach cria exercícios próprios (com upload de mídia), visíveis só
     no tenant; pode "clonar e ajustar" um exercício global.
4. Taxonomia mínima: grupo muscular, equipamento, padrão de movimento, nível.
5. Meta de lançamento: ~300 exercícios globais curados e traduzidos cobrindo
   musculação padrão de academia.

## Consequências

- Custo financeiro zero; custo real é o trabalho de curadoria (estimar ~2–3 semanas,
  paralelizável com o desenvolvimento usando planilha → seed script).
- O muscle map depende da curadoria do mapeamento de músculos — entra no caminho
  crítico do marco correspondente.
- Compliance de licença auditável por registro em banco.
