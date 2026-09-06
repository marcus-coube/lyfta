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

## - [x] P2.2 Serviço assessment — esqueleto + schema

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

## - [x] P2.3 assessment — API completa

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

## - [x] P2.4 Flutter — aluno: tela Evolução

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

## - [x] P2.5 Flutter — professor: evolução do aluno

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

### P2.2 (2026-09-02, Mac)

- **Quarto serviço, bootstrap idêntico ao workout (P1.1):** chi+pgxpool+slog,
  `internal/security/jwt.go` e `internal/repo/{pool,tenant}.go` duplicados
  (nem uma linha importada de outro serviço — ADR-013 §2), `/healthz` público
  e `/v1/whoami` autenticado como sonda. Nenhum handler de negócio ainda: a
  API completa (POST/GET/DELETE, presign de foto, summary) é a P2.3.
- **Sem S3 nesta tarefa.** O plano só pede "esqueleto + schema"; presign de
  foto é escopo explícito da P2.3. `internal/config` não exige `S3_*` — vai
  ganhar isso junto com o handler de upload, para não travar o boot do
  serviço por uma variável que ainda não é usada.
- **As 3 tabelas são fatos "flat" por aluno**, sem a árvore do workout: uma
  única policy de RLS por tabela (`tenant_isolation`, USING+WITH CHECK), como
  `workout_set_logs`/`prescribed_sets` — não a policy dupla de `exercises`,
  porque não há registro global aqui. Índice `(tenant_id, student_id,
  measured_at|taken_at DESC)` em cada uma: é exatamente o que a paginação por
  cursor da P2.3 vai percorrer.
- **Só os campos que o plano listou** — nenhum `created_by` em
  `body_measurements`/`bioimpedance_records` (a P2.3 decide se o autor do
  lançamento importa; hoje não muda schema, é dado de auditoria opcional).
  Adicionei `created_at` nas três tabelas (não estava na lista do plano, mas é
  o padrão do repositório — `exercises`, `workout_sessions` etc. — e serve de
  desempate estável quando duas medidas caem no mesmo dia).
- **`progress_photos.media_key` é `NOT NULL`**, diferente de
  `exercises.media_url` (opcional lá porque um exercício pode não ter mídia):
  uma foto sem mídia não é um registro válido.
- **Teste de RLS sem repositório de domínio ainda** (mesmo caminho que
  `TestSetLogsAreAppendOnly` usou no workout antes do P1.5 existir): SQL cru
  via `repo.WithTenant`, porque construir `internal/repo/assessment.go` cedo
  seria antecipar a P2.3. `TestCrossTenantIsolation` grava um registro de cada
  tabela sob o tenant A e confirma que B vê zero linhas nas três; um segundo
  teste (`TestRLSBlocksWriteWithoutTenantContext`) cobre a metade que o
  round-trip não cobre — insert direto no pool, sem `SET LOCAL
  app.tenant_id`, é recusado pela `FORCE ROW LEVEL SECURITY`.
- **Reversibilidade verificada de verdade:** `migrate ... down -all` seguido
  de `up` de novo, depois os testes rodando limpos — não só leitura visual
  das 4 migrations.
- **CI não precisou de ajuste.** O job `discover` já lista serviços por
  `backend/<svc>/go.mod`, cria `lyfta_assessment` a partir de
  `DB_NAME: lyfta_${{ matrix.service }}` e roda migrations+testes como
  `lyfta_app` — o mesmo mecanismo que pegou o workout automaticamente na
  P0.7 pegou o assessment sem editar o workflow.
- **Verificado (Mac):** `go vet` limpo, `gofmt -l` limpo, **2 testes verdes**;
  smoke manual com `identity` e `assessment` no ar — signup real gerando
  token EdDSA, `/v1/whoami` do assessment devolvendo `tenant_id`/`roles`
  corretos, 401 sem token e com token malformado.

### P2.3 (2026-09-02, Mac)

- **Duas portas por recurso, igual ao histórico do P2.1:** `/me/...` resolve
  o aluno pela claim (sem parâmetro de aluno na URL — nenhum token lê/apaga o
  registro de outra pessoa) e `/students/{id}/...` é do coach, qualquer
  professor do tenant (mesmo critério do P1.4/P2.1; o vínculo coach↔aluno
  segue dívida do identity). `/me/...` não tem `RequireRole`: é o mesmo
  critério do `/me/plan` do workout — funciona para qualquer subject
  autenticado, só que na prática só o aluno tem o que ler.
- **`created_by` ficou de fora**, e a dívida da P2.2 segue aberta: nenhuma das
  três tabelas registra quem lançou (aluno ou coach). Não é regra do Aceite
  desta tarefa (só permissão + deltas), e a P2.4/P2.5 não pedem essa
  informação na tela. Se o produto precisar de "lançado por" na ficha,
  entra como migration nova, sem tocar as já commitadas.
- **Presigner do assessment é mais simples que o do workout**, não por
  economia e sim porque o dado guardado é diferente: `progress_photos.media_key`
  guarda a **key crua** (não uma `media_url`), então não precisou duplicar
  `KeyFromURL`/`KeyForTenant`/`ResolveURL` — só `ObjectKey`, `PresignPut`,
  `ReadURL` e um `ValidKeyForStudent` novo (prefixo
  `tenants/{t}/students/{s}/photos/`) que é o par de segurança do presign:
  sem ele, um `media_key` forjado apontando para a pasta de outro aluno
  seria aceito no cadastro da foto. Key layout, tipos (jpeg/png/webp) e teto
  (15 MB) exatamente como pedido no plano; `S3_*` entrou no `config` como
  obrigatório, igual ao workout — quitando a dívida anotada na P2.2.
- **Presign tem duas rotas** (`/me/media/presign`, `/students/{id}/media/presign`)
  porque, diferente da mídia de exercício do workout (só tenant no caminho),
  a foto carrega o aluno na key — o aluno sobe a própria foto (P2.4) e o
  coach sobe pela ficha (avaliação presencial), cada um assinando a pasta
  certa.
- **Cursor keyset por `(measured_at|taken_at, id)` descendente**, formato
  opaco igual ao do histórico/biblioteca do workout — duplicado, não
  importado (ADR-013 §2). As três listagens reusam a mesma função de
  parsing de cursor/limit (`parseListQuery`) porque são idênticas: só muda a
  tabela.
- **O resumo reusa `List(..., limit=2)`** em vez de uma query dedicada de
  "penúltimo registro": os dois primeiros itens da listagem cronológica já
  são o mais recente e o anterior, então o delta sai do mesmo caminho que a
  tela de histórico usa. Delta é **nulo, não zero**, quando falta o lado
  anterior — combinado com o P2.1 (`max_load_kg` nulo em exercício sem
  carga): "não dá para saber" não pode desenhar como "não mudou nada".
- **Validação no handler espelha os CHECK/NUMERIC do schema da P2.2**
  (ex.: `waist_cm` até 9999.9, `body_fat_pct` 0–100): sem isso um valor fora
  da precisão da coluna estouraria como `internal_error` em vez de
  `validation_error` traduzível.
- **CI precisou de ajuste, ao contrário da P2.2:** o step "Subir MinIO" era
  condicional a `matrix.service == 'workout'`; passou a subir também para
  `assessment`. A suíte de handler não depende disso (presign é operação
  offline, mesma prova do `router_test.go` do workout), mas o round-trip de
  upload real (`internal/media/presigner_test.go`, duplicado do P1.2 com
  JPEG em vez de GIF) precisa do MinIO no ar — sem o ajuste ficaria pulado
  silenciosamente fora do CI e falhando dentro dele.
- **Verificado (Mac):** `gofmt -l` limpo, `go vet` limpo, **29 testes
  verdes** (`internal/repo`: round-trip e paginação dos três agregados;
  `internal/media`: round-trip de upload real no MinIO + rejeições offline;
  `internal/http`: CRUD ponta a ponta nas duas portas, isolação entre
  tenants e entre alunos do mesmo tenant, presign feliz/rejeitado, key
  forjada rejeitada, resumo com deltas corretos e sem anterior). Smoke com
  `identity`+`assessment` reais no ar (matando processos `go run` obsoletos
  de uma sessão anterior antes, para não validar contra binário velho):
  signup → coach lança 2 medidas + 1 bioimpedância para um `student_id`
  avulso (sem cadastro no identity — o serviço não tem FK, ADR-013 §2) →
  presign real → `PUT` de bytes de verdade no MinIO → cadastro da foto →
  `GET /summary` devolveu `weight_kg: -3`, `waist_cm: -3.5`,
  `photo_count: 1`, e um segundo tenant (signup separado) leu lista vazia
  nas mesmas rotas.

### P2.4 (2026-09-04, Mac)

- **`features/evolution/` segue `domain/`+`data/`+`presentation/` como o
  resto do app, mas com um quinto diretório, `widgets/`, no nível da
  feature (não dentro de `presentation/`) — é o que o plano pediu
  explicitamente para o P2.5 reusar sem duplicar código: `load_chart_panel`,
  `exercise_selector`, `measurement_form`/`list`, `bioimpedance_form`/`list`,
  `photo_grid`, `photo_compare`, `evolution_date_field`, `delta_badge` e
  `pose_label` são todos "burros" (só recebem dados e callbacks, nunca
  falam com repositório) para o coach poder embrulhá-los com o controller
  dele sem tocar o widget.
- **Dois serviços, um repositório só.** `EvolutionRepository` guarda dois
  `Dio` (`workout` para o histórico do P2.1, `assessment` para
  medidas/bioimpedância/fotos do P2.3) — nenhum import de código entre eles
  (ADR-013 §2). `assessmentApiClientProvider` entrou em `core/http/providers.dart`,
  espelhando o `workoutApiClientProvider` (P0.6).
- **O range do gráfico (1m/3m/6m/tudo) pagina no cliente.** Confirmando a
  nota do P2.1: `/exercises/{id}/history` não tem `?since=`.
  `EvolutionRepository.exerciseHistory` pagina pelo cursor até a sessão mais
  antiga da página passar do corte, com teto de 40 páginas (60 itens cada)
  — 2400 pontos antes de desistir, folga generosa para o horizonte do MVP.
  Se algum dia isso morder de verdade, o parâmetro entra no servidor.
- **Seleção de exercício não escreve estado até o aluno escolher.**
  `loadSelectionProvider.exerciseId` começa nulo; a tela deriva um "efetivo"
  (`selection.exerciseId ?? items.first`) só na renderização, e
  `exerciseHistoryProvider` virou `family` sobre `(exerciseId, since)` em
  vez de ler `loadSelectionProvider` direto — evita a race de sincronizar
  dois providers com `ref.listen`/callback de frame só para mostrar o
  primeiro exercício da lista por padrão.
- **Deltas coloridos são por sinal, não por campo:** `DeltaBadge` pinta
  `success` quando o valor cai e `danger` quando sobe, para todo campo
  (peso, cintura, %gordura, ...). É uma simplificação consciente — ganhar
  peso pode ser a meta de alguém —, documentada no código; sem um objetivo
  declarado por medida, "queda = verde" é a leitura mais comum na maioria
  dos campos (cintura, gordura). Vira dívida se o produto precisar de meta
  por medida.
- **Fotos: compressão sempre em JPEG**, independente do formato de origem
  escolhido no picker (`flutter_image_compress`, `quality: 82`,
  `minWidth/minHeight: 1280`) — o `content_type` do presign nunca depende
  de inspecionar a extensão do arquivo. O comparador antes/depois guarda a
  seleção por `id` da foto, não pela instância: a lista é substituída
  inteira a cada `refresh()` do controller, e um `DropdownButtonFormField`
  cujo `value` não é `identical` a nenhum item da lista nova quebra a
  asserção do widget — achado rodando o teste manual local antes de
  escrever o teste automatizado.
- **Sem mudança na permissão de câmera do Android.** `image_picker` usa
  intent implícita para `ImageSource.camera` (delega para o app de câmera
  do sistema), então não precisa de `<uses-permission CAMERA>` no
  `AndroidManifest.xml` — só precisaria se o app quisesse controlar a
  câmera diretamente. Fica como algo a confirmar no Aceite manual em
  device: nesta sessão não havia como validar o fluxo de câmera de verdade
  (só galeria foi exercitada, com uma imagem local no Chrome).
- **Formatação numérica duplicada de propósito.**
  `shared/format/metric_format.dart` repete a lógica de
  `features/workout/presentation/prescription_format.dart#formatLoad` (sem
  `.0` decorativo) — feature não importa feature (guideline flutter.md).
  Unificar os dois num único helper em `shared/` é limpeza futura, não
  bloqueia esta tarefa.
- **Escopo não expandido:** nenhuma rota `/students/{id}/...` do coach foi
  implementada no repositório ou nos controllers — só `/me/...`. O P2.5 vai
  precisar da própria variante (ou generalizar `EvolutionRepository` para
  aceitar um `studentId` opcional), decisão que fica para quando aquela
  tarefa for aberta.
- **Verificado (Mac):** `flutter analyze` limpo, guard de strings limpo,
  **42 testes verdes** (4 novos do `MeasurementForm`: preenchimento parcial
  com um campo, preenchimento parcial em vários campos aceitando vírgula
  decimal pt-BR, formulário vazio bloqueado com a mensagem de erro visível,
  e observação sozinha também bloqueada — "não é uma medida"). Rodado só no
  Chrome nesta sessão (sem toque em dispositivo real); o Aceite manual
  completo — aluno em Android lançando medida+bioimpedância+foto e vendo o
  gráfico de carga real do P1 (dados do E2E do P1.8: 1020 kg no treino A) —
  fica para o humano. Roteiro sugerido: subir `identity`+`workout`+
  `assessment` locais, `flutter run -d emulator-5554
  --dart-define=IDENTITY_BASE_URL=http://10.0.2.2:8081
  --dart-define=WORKOUT_BASE_URL=http://10.0.2.2:8082
  --dart-define=ASSESSMENT_BASE_URL=http://10.0.2.2:8083`, logar como o
  aluno do E2E do P1.8, abrir a aba Evolução, conferir que a aba Carga
  mostra a série real, lançar uma medida parcial, uma leitura de
  bioimpedância e uma foto (câmera **e** galeria) e conferir que aparecem
  nas listas/grade sem recarregar o app.

### P2.5 (2026-09-06, Mac)

- **O escopo virou um valor, não um segundo repositório.** `EvolutionScope`
  (`me()` ou `student(id)`) carrega só o prefixo da rota — `/v1/me` ou
  `/v1/students/{id}` —, que é igual nos dois serviços (P2.1 e P2.3). Todo
  método do `EvolutionRepository` passou a recebê-lo, e os controllers
  viraram `family` por escopo. Sem isso, ou o coach ganhava uma cópia de
  cada controller e widget, ou o repositório teria dois métodos por rota; a
  dívida anotada no P2.4 fecha aqui.
- **Cada aluno tem seu próprio estado, inclusive a seleção do gráfico.**
  `loadSelectionProvider` também é família: abrir a ficha de outro aluno não
  herda um exercício que ele nunca treinou, e voltar para a lista não deixa
  a seleção anterior grudada.
- **A ficha é a mesma `EvolutionScreen`, com uma aba a mais.** No escopo do
  coach entra o Resumo (`GET /students/{id}/summary`), que a tela do aluno
  não tem porque o `assessment` não expõe `/me/summary` — quem já vê as três
  listas inteiras não precisa do condensado. O `summary()` do repositório
  tem `assert(scope.isCoach)` para essa porta não ser chamada por engano.
- **Evolução entrou como ação ao lado do plano na lista de alunos**, não no
  lugar dele: são as duas coisas que o professor faz com um aluno, e o toque
  no card segue abrindo o plano como no P1.6. A rota
  `/students/{id}/evolution` é de primeira classe (mesmo motivo do builder:
  recarregar a página na web), com o nome do aluno vindo por `extra` só para
  o título — sem ele a tela abre igual.
- **Defeito de gráfico achado no Aceite e corrigido aqui:** sem `interval`,
  o `fl_chart` chama o `getTitlesWidget` em frações do eixo (0.0, 0.2, 0.4…)
  e o `round()` mapeava várias delas para o mesmo ponto — o eixo X saía com
  a mesma data repetida quatro vezes seguidas. O P2.4 não viu porque a tela
  do aluno nunca teve dados nesta máquina. Passou a valer `interval:
  labelStep` mais o descarte de valor não inteiro.
- **Verificado (Mac):** `flutter analyze` limpo, guard de strings limpo e
  **44 testes verdes** (2 novos: a mesma tela montada nos dois escopos —
  3 abas e nenhuma chamada de resumo no do aluno; 4 abas, resumo pedido uma
  vez e nenhuma chamada vazando para `/me` no do coach). Aceite exercitado no
  Chrome com `identity`+`workout`+`assessment` no ar, sobre um cenário criado
  para isso (coach, aluna convidada e aceita, 3 medidas, 2 bioimpedâncias e 4
  sessões de treino pelo `POST /sync/workout-logs`): as 4 abas navegadas com
  dado real — Resumo com deltas -3 kg / -3,5 cm / -4,6 %, Medidas com os três
  registros e deltas coloridos, Carga desenhando 32,5→40 kg (e o volume
  877,5→1160 kg no toggle, com o range de 1 mês cortando para os dois últimos
  pontos) e Fotos no estado vazio com o botão de lançamento do coach.
- **Dívida que segue aberta:** `created_by` continua fora das tabelas do
  `assessment` (P2.2/P2.3), então uma medida lançada pelo coach é
  indistinguível de uma lançada pelo aluno; e o vínculo coach↔aluno continua
  sendo dívida do `identity` — qualquer professor do tenant abre a ficha de
  qualquer aluno, o mesmo critério do P1.4/P2.1.
