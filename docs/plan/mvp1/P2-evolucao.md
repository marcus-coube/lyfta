# P2 — Evolução (carga, fotos, medidas, bioimpedância)

Meta da fase: aluno vê progressão de carga em gráfico, registra fotos antes/depois,
medidas e bioimpedância (digitadas — ADR-012 §2); professor acompanha tudo.

Refs normativas: ADR-012 (escopo digitado), ADR-013, ADR-001 (RLS).

---

## - [x] P2.1 workout — API de histórico por exercício

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

### P2.1 (2026-09-02, Mac)

- **A agregação é toda em SQL, num CTE só.** `effective` aplica o
  `effectiveLogFilter` que já existia (log corrigido por `set_revision` some da
  leitura, ADR-003 §5), `agg` soma por sessão e `top` escolhe a melhor série
  com `DISTINCT ON`. Trazer log a log para somar em Go custaria uma linha por
  série executada na vida do aluno — e o gráfico do P2.4 pede meses.
- **O eixo é o `exercise_id`, não o plano.** É o que faz a série sobreviver a
  republicar versão e a trocar de plano (ADR-004 §2) — o mesmo motivo pelo qual
  a "carga anterior" do P1.5 já casava por exercício. Nenhuma migration nova: o
  índice `(tenant_id, exercise_id, performed_at DESC)` do P1.1 é exatamente o
  que a consulta percorre.
- **`top_set` é a maior carga, desempatando por mais reps e depois pela série
  mais cedo.** É a linha que o aluno lembra ("bati 45 por 8"), e por isso vai
  separada dos agregados em vez de ser derivada na tela.
- **`max_load_kg` é nulo, não zero, em exercício sem carga.** Corpo livre e
  trabalho por tempo existem na biblioteca; zero faria o gráfico desenhar uma
  linha no chão em vez de mudar de métrica.
- **Duas portas para a mesma leitura:** `/me/...` resolve o aluno pela claim
  (nenhum token lê o histórico de outra pessoa, nem por engano — a rota não tem
  parâmetro de aluno) e `/students/{id}/...` vive no grupo de professor. Ler o
  histórico de um aluno é de **qualquer professor do tenant**, o mesmo critério
  que o P1.4 usou para ler plano; o vínculo coach↔aluno continua sendo dívida
  do identity.
- **A variante coach de `/exercises/logged` entrou junto**, embora o plano só
  cite a do aluno: sem ela a aba Carga do P2.5 não teria de onde montar o
  seletor de exercício, e é o mesmo handler com o `student_id` vindo da URL.
- **Ordem decrescente e cursor keyset `(performed_at, session_id)`.** A tela
  abre no presente e pagina para trás; quem inverte para o eixo do tempo é o
  cliente. O range 1m/3m/6m do P2.4 se resolve paginando até passar da data —
  não há `?since=`, e se a tela sofrer com isso vira um parâmetro depois.
- **Exercício desconhecido é 404, não página vazia:** sem isso a tela não
  distingue "id errado" de "ainda não treinou isso". O índice também descarta
  exercício que sumiu da biblioteca — o seletor não tem o que desenhar sem
  nome nem mídia.
- **Descoberta de ambiente:** `source .env` não sobe os serviços nesta máquina
  (o `<` do `MAIL_FROM` vira redireção) e um loader ingênuo linha a linha
  **também** falha: `JWT_PUBLIC_KEY` vem entre aspas e o PEM chega inválido. O
  loader precisa tirar as aspas do valor. Reforça a nota do P1.8: vale um
  `--env-file` ou script de dev.
- **Verificado (Mac):** `go vet` limpo e **62 testes verdes** (7 novos: 4 de
  repo — três sessões com máximo/volume/top set corretos, revisão de série
  fora da conta, paginação sem repetir ponto e índice só com o que foi
  treinado; 3 de handler — as duas portas vendo a mesma série, aluno barrado na
  rota do professor, tenant estrangeiro sem nada, id malformado e cursor
  inválido). Smoke com os dois serviços no ar sobre os dados que o E2E do P1.8
  deixou: o histórico devolveu **1020 kg** para o treino A e **432 kg** para o
  C, os mesmos números que o app do aluno mostrou no emulador, e
  `?locale=en` trouxe "Crunch"/"Dumbbell lunge" — o endpoint resolve locale, o
  app é que ainda não manda (dívida do P1.8).
