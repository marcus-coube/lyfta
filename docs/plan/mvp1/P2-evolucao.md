# P2 — Evolução (carga, fotos, medidas, bioimpedância)

Meta da fase: aluno vê progressão de carga em gráfico, registra fotos antes/depois,
medidas e bioimpedância (digitadas — ADR-012 §2); professor acompanha tudo.

Refs normativas: ADR-012 (escopo digitado), ADR-013, ADR-001 (RLS).

---

## - [ ] P2.1 workout — API de histórico por exercício

**Objetivo:** dados prontos para o gráfico de progressão.
**Endpoints:** `GET /v1/me/exercises/{exercise_id}/history` (e variante coach
`GET /v1/students/{id}/exercises/{exercise_id}/history`): série temporal por sessão
com `max_load_kg`, `total_volume` (Σ reps×carga), `top_set` (reps×carga do melhor
set), paginação por cursor de data; agregação em SQL direto sobre
`workout_set_logs` (usa `performed_at`, ignora logs revisados via `revises`).
Lista `GET /v1/me/exercises/logged` (exercícios com histórico, para o índice da
tela Evolução).
**Aceite:** teste com 3 sessões calcula max/volume corretos e exclui sets revisados.

## - [ ] P2.2 Serviço assessment — esqueleto + schema

**Objetivo:** serviço de avaliação física de pé.
**Passos:** bootstrap padrão (chi, pgx, migrations, JWT, RLS — igual P1.1).
Migrations:
- `body_measurements (id, tenant_id, student_id, measured_at date, weight_kg,
  height_cm, neck_cm, shoulder_cm, chest_cm, waist_cm, abdomen_cm, hip_cm,
  arm_l_cm, arm_r_cm, thigh_l_cm, thigh_r_cm, calf_l_cm, calf_r_cm, notes)` —
  campos nullable (registra-se o que mediu).
- `bioimpedance_records (id, tenant_id, student_id, measured_at date,
  body_fat_pct, muscle_mass_kg, visceral_fat, body_water_pct, bone_mass_kg,
  bmr_kcal, notes)` — **entrada manual** (ADR-012).
- `progress_photos (id, tenant_id, student_id, taken_at date, pose: front|side|
  back, media_key, notes)`.
**Aceite:** migrations limpas; RLS testada cross-tenant.

## - [ ] P2.3 assessment — API completa

**Objetivo:** CRUD + listagens para app.
**Endpoints:** para cada recurso: `POST`, `GET` lista (cursor por `measured_at`/
`taken_at` desc), `DELETE` (aluno apaga o próprio; coach os do aluno dele);
presign de foto (`POST /v1/media/presign`, key
`tenants/{t}/students/{s}/photos/{uuid}.jpg`, jpeg/png/webp, 15 MB);
`GET /v1/students/{id}/summary` (coach): última medida, última bioimpedância,
contagem de fotos, deltas vs registro anterior (peso, % gordura, cintura).
**Permissões:** aluno escreve os seus; coach lê os dos seus alunos e também pode
lançar (comum em avaliação presencial).
**Aceite:** testes de permissão (aluno A não lê aluno B; coach de outro tenant não
lê nada); deltas do summary corretos.

## - [ ] P2.4 Flutter — aluno: tela Evolução

**Objetivo:** a aba Evolução completa do aluno.
**Passos:**
1. `fl_chart`: gráfico de linha por exercício (toggle max carga × volume), seletor
   de exercício a partir de `/exercises/logged`, range 1m/3m/6m/tudo.
2. Medidas: form de lançamento (só campos preenchidos são enviados), lista
   histórica com deltas coloridos; bioimpedância idem.
3. Fotos: captura/galeria (`image_picker`), upload presigned com compressão
   (`flutter_image_compress`), grade por data/pose e **comparador antes/depois**
   (duas fotos lado a lado com seletor de datas).
**Aceite:** aluno lança medida+bioimpedância+foto no Android e vê gráfico de carga
real do P1; teste de widget do form de medidas (parcial ok, vazio bloqueado).

## - [ ] P2.5 Flutter — professor: evolução do aluno

**Objetivo:** o coach enxerga o progresso de cada aluno.
**Passos:** na ficha do aluno (shell professor): abas Resumo (summary do P2.3 com
deltas), Carga (mesmos gráficos, escolhendo exercício), Medidas, Fotos
(comparador). Reusar os widgets do P2.4 (extrair para `features/evolution/widgets/`
compartilhado entre papéis). Lançamento pelo coach habilitado.
**Aceite:** no web, coach abre ficha do aluno e navega as 4 abas com dados reais;
mesmos widgets renderizam nos dois shells sem duplicação de código.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
