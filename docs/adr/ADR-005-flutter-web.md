# ADR-005 — Web: Flutter Web agora, reavaliação programada

**Status:** Aceito (com gatilho de revisão)
**Data:** 2026-07-02

## Contexto

A experiência web é desktop-first (gestão de alunos, workout builder, financeiro,
relatórios). Flutter Web mantém codebase único, mas tem fraquezas conhecidas: bundle
inicial pesado, tabelas densas, drag-and-drop, seleção de texto e atalhos.

## Decisão

**MVP inteiro em Flutter Web**, com salvaguardas para manter a porta de migração aberta:

1. A API é o único contrato: nenhuma lógica de negócio no cliente; um futuro admin web
   nativo consumiria a mesma API sem mudanças no backend.
2. O workout builder do MVP usa formulários e listas reordenáveis simples —
   **drag-and-drop rico fica explicitamente fora do MVP** (já sinalizado no doc 007).
3. Mitigações obrigatórias: renderer CanvasKit para desktop, deferred loading por
   feature, skeleton de carregamento, paginação server-side em toda tabela.

**Gatilho de reavaliação:** ao final do marco M5 (financeiro/dashboard — ver plano de
documentação), avaliar com usuários reais: tempo de carga, usabilidade das tabelas e
do builder. Se insuficiente, migra-se apenas o admin desktop para web nativa
(React/Next), mantendo Flutter para mobile e para o aluno.

## Consequências

- Um codebase só, entrega mais rápida para dev solo — benefício dominante agora.
- Risco contido por design: o pior cenário é reescrever só a casca admin, não o produto.
