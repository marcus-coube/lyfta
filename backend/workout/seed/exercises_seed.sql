-- Seed da biblioteca GLOBAL de exercícios (P1.3) — 41 exercícios básicos de
-- musculação nos três locales do ADR-011 (pt-BR, pt-PT, en).
--
-- Exercício global é `tenant_id NULL` (ADR-010 §3): legível por qualquer
-- tenant, editável por nenhum. As policies de escrita da tabela **não cobrem**
-- tenant_id NULL de propósito, então este arquivo só roda como superusuário:
--
--     psql -U postgres -d lyfta_workout -f backend/workout/seed/exercises_seed.sql
--
-- Não é migration: dado de conteúdo, não de schema. Roda depois das migrations
-- e é idempotente (id determinístico por slug + ON CONFLICT), então pode ser
-- reexecutado a cada atualização de texto. Meta de lançamento do ADR-010 §5 é
-- ~300 exercícios curados; estes 41 são o suficiente para montar treinos
-- reais em dev e demo.
--
-- Os códigos de músculo e equipamento são a taxonomia de
-- internal/domain/library.go — quem traduz para a UI é o app (ADR-011 §5).

BEGIN;

CREATE TEMP TABLE seed_exercises (
    slug           TEXT PRIMARY KEY,
    primary_muscle TEXT NOT NULL,
    equipment      TEXT NOT NULL,
    level          TEXT NOT NULL,
    name_pt_br     TEXT NOT NULL,
    instr_pt_br    TEXT NOT NULL,
    name_pt_pt     TEXT NOT NULL,
    instr_pt_pt    TEXT NOT NULL,
    name_en        TEXT NOT NULL,
    instr_en       TEXT NOT NULL,
    -- Id determinístico a partir do slug: o mesmo exercício tem o mesmo UUID
    -- em toda máquina e em todo ambiente, o que torna o seed reexecutável e
    -- deixa planos de dev apontando para ids estáveis.
    id UUID GENERATED ALWAYS AS (
        ('00000000-0000-7000-8000-' || substr(md5(slug), 1, 12))::uuid
    ) STORED
) ON COMMIT DROP;

INSERT INTO seed_exercises
    (slug, primary_muscle, equipment, level,
     name_pt_br, instr_pt_br, name_pt_pt, instr_pt_pt, name_en, instr_en)
VALUES
    ('supino-reto-barra', 'chest', 'barbell', 'intermediate', 'Supino reto com barra', 'Deitado no banco, desça a barra até o peito e empurre até estender os cotovelos.', 'Supino plano com barra', 'Deitado no banco, desce a barra até ao peito e empurra até estenderes os cotovelos.', 'Barbell bench press', 'Lying on a flat bench, lower the bar to your chest and press up until the elbows extend.'),
    ('supino-inclinado-halteres', 'chest', 'dumbbell', 'intermediate', 'Supino inclinado com halteres', 'No banco a 30-45 graus, empurre os halteres acima do peito sem bater um no outro.', 'Supino inclinado com halteres', 'No banco a 30-45 graus, empurra os halteres acima do peito sem os bateres.', 'Incline dumbbell press', 'On a 30-45 degree bench, press the dumbbells above your chest without clashing them.'),
    ('crucifixo-maquina', 'chest', 'machine', 'beginner', 'Crucifixo na máquina', 'Cotovelos levemente flexionados, junte os braços à frente do peito e volte devagar.', 'Voador na máquina', 'Cotovelos levemente fletidos, junta os braços à frente do peito e regressa devagar.', 'Pec deck fly', 'With elbows slightly bent, bring your arms together in front of the chest and return slowly.'),
    ('crossover-polia', 'chest', 'cable', 'intermediate', 'Crossover na polia', 'Com as polias altas, cruze as mãos à frente do quadril mantendo o peito aberto.', 'Cruzamento de cabos', 'Com as polias altas, cruza as mãos à frente da anca mantendo o peito aberto.', 'Cable crossover', 'With high pulleys, bring your hands together in front of the hips keeping the chest open.'),
    ('flexao-de-braco', 'chest', 'bodyweight', 'beginner', 'Flexão de braço', 'Corpo alinhado da cabeça aos calcanhares, desça até o peito quase tocar o chão.', 'Flexão de braços', 'Corpo alinhado da cabeça aos calcanhares, desce até o peito quase tocar o chão.', 'Push-up', 'Keep the body in a straight line and lower until your chest nearly touches the floor.'),
    ('puxada-frente-pulley', 'back', 'cable', 'beginner', 'Puxada frontal na polia', 'Puxe a barra até a altura do queixo levando os cotovelos para baixo e para trás.', 'Puxada à frente na polia', 'Puxa a barra até à altura do queixo levando os cotovelos para baixo e para trás.', 'Lat pulldown', 'Pull the bar to chin height, driving the elbows down and back.'),
    ('barra-fixa', 'back', 'bodyweight', 'advanced', 'Barra fixa', 'Pendurado na barra, puxe o corpo até o queixo passar a barra e desça controlando.', 'Elevação na barra fixa', 'Suspenso na barra, puxa o corpo até o queixo passar a barra e desce controlado.', 'Pull-up', 'Hanging from the bar, pull until your chin clears it and lower under control.'),
    ('remada-curvada-barra', 'back', 'barbell', 'intermediate', 'Remada curvada com barra', 'Tronco inclinado e coluna neutra, puxe a barra até o abdômen e volte devagar.', 'Remada inclinada com barra', 'Tronco inclinado e coluna neutra, puxa a barra até ao abdómen e regressa devagar.', 'Barbell bent-over row', 'With a hinged torso and neutral spine, row the bar to your abdomen and lower slowly.'),
    ('remada-baixa-polia', 'back', 'cable', 'beginner', 'Remada baixa na polia', 'Sentado, puxe o triângulo até o abdômen mantendo o tronco firme e ombros baixos.', 'Remada sentada na polia', 'Sentado, puxa o triângulo até ao abdómen mantendo o tronco firme e ombros baixos.', 'Seated cable row', 'Seated, pull the handle to your abdomen keeping the torso still and shoulders down.'),
    ('remada-unilateral-halter', 'back', 'dumbbell', 'beginner', 'Remada unilateral com halter', 'Apoiado no banco, puxe o halter junto ao corpo até a altura das costelas.', 'Remada a um braço com haltere', 'Apoiado no banco, puxa o haltere junto ao corpo até à altura das costelas.', 'One-arm dumbbell row', 'Supported on a bench, row the dumbbell close to your body up to rib height.'),
    ('levantamento-terra', 'lower_back', 'barbell', 'advanced', 'Levantamento terra', 'Quadril para trás e coluna neutra, suba a barra rente às pernas estendendo quadril e joelhos.', 'Peso morto', 'Anca para trás e coluna neutra, sobe a barra rente às pernas estendendo anca e joelhos.', 'Deadlift', 'Hinge at the hips with a neutral spine and lift the bar close to your legs, extending hips and knees.'),
    ('desenvolvimento-halteres', 'shoulders', 'dumbbell', 'intermediate', 'Desenvolvimento com halteres', 'Sentado com tronco apoiado, empurre os halteres acima da cabeça sem arquear as costas.', 'Desenvolvimento com halteres', 'Sentado com tronco apoiado, empurra os halteres acima da cabeça sem arquear as costas.', 'Dumbbell shoulder press', 'Seated with back supported, press the dumbbells overhead without arching your back.'),
    ('desenvolvimento-maquina', 'shoulders', 'machine', 'beginner', 'Desenvolvimento na máquina', 'Ajuste o banco na altura dos ombros e empurre até quase estender os cotovelos.', 'Desenvolvimento na máquina', 'Ajusta o banco à altura dos ombros e empurra até quase estenderes os cotovelos.', 'Machine shoulder press', 'Set the seat at shoulder height and press until the elbows are almost extended.'),
    ('elevacao-lateral', 'shoulders', 'dumbbell', 'beginner', 'Elevação lateral', 'Suba os halteres pelos lados até a altura dos ombros, sem balançar o tronco.', 'Elevação lateral', 'Sobe os halteres pelos lados até à altura dos ombros, sem balançares o tronco.', 'Lateral raise', 'Raise the dumbbells out to the sides up to shoulder height without swinging the torso.'),
    ('elevacao-frontal', 'shoulders', 'dumbbell', 'beginner', 'Elevação frontal', 'Suba os halteres à frente até a altura dos ombros e desça controlando o movimento.', 'Elevação frontal', 'Sobe os halteres à frente até à altura dos ombros e desce controlando o movimento.', 'Front raise', 'Raise the dumbbells in front of you to shoulder height and lower under control.'),
    ('crucifixo-inverso', 'shoulders', 'dumbbell', 'intermediate', 'Crucifixo inverso', 'Tronco inclinado à frente, abra os braços para trás juntando as escápulas.', 'Voador invertido', 'Tronco inclinado à frente, abre os braços para trás juntando as omoplatas.', 'Reverse fly', 'With the torso hinged forward, open the arms back squeezing the shoulder blades.'),
    ('encolhimento-halteres', 'traps', 'dumbbell', 'beginner', 'Encolhimento com halteres', 'Eleve os ombros em direção às orelhas segurando um segundo no topo.', 'Encolhimento de ombros com halteres', 'Eleva os ombros em direção às orelhas segurando um segundo no topo.', 'Dumbbell shrug', 'Lift your shoulders toward your ears and hold for a second at the top.'),
    ('rosca-direta-barra', 'biceps', 'barbell', 'beginner', 'Rosca direta com barra', 'Cotovelos junto ao corpo, suba a barra até o peito sem balançar o tronco.', 'Rosca bíceps com barra', 'Cotovelos junto ao corpo, sobe a barra até ao peito sem balançares o tronco.', 'Barbell curl', 'Keeping the elbows at your sides, curl the bar to chest height without swinging.'),
    ('rosca-alternada-halteres', 'biceps', 'dumbbell', 'beginner', 'Rosca alternada com halteres', 'Suba um halter de cada vez girando o punho para fora no fim do movimento.', 'Rosca alternada com halteres', 'Sobe um haltere de cada vez rodando o punho para fora no fim do movimento.', 'Alternating dumbbell curl', 'Curl one dumbbell at a time, rotating the wrist outward at the top.'),
    ('rosca-martelo', 'biceps', 'dumbbell', 'beginner', 'Rosca martelo', 'Com as palmas viradas para dentro, suba os halteres mantendo os cotovelos parados.', 'Rosca martelo', 'Com as palmas viradas para dentro, sobe os halteres mantendo os cotovelos parados.', 'Hammer curl', 'With palms facing in, curl the dumbbells keeping the elbows still.'),
    ('rosca-scott', 'biceps', 'machine', 'intermediate', 'Rosca scott', 'Braços apoiados no banco inclinado, suba a barra sem tirar os cotovelos do apoio.', 'Rosca no banco Scott', 'Braços apoiados no banco inclinado, sobe a barra sem tirares os cotovelos do apoio.', 'Preacher curl', 'With the arms on the pad, curl the bar without lifting the elbows off the support.'),
    ('triceps-pulley-corda', 'triceps', 'cable', 'beginner', 'Tríceps na polia com corda', 'Cotovelos colados ao corpo, estenda os braços abrindo a corda no final.', 'Extensão de tríceps na polia com corda', 'Cotovelos junto ao corpo, estende os braços abrindo a corda no final.', 'Rope triceps pushdown', 'Keep the elbows pinned and extend the arms, spreading the rope at the bottom.'),
    ('triceps-testa', 'triceps', 'barbell', 'intermediate', 'Tríceps testa', 'Deitado, flexione os cotovelos levando a barra até a testa e estenda sem abrir os braços.', 'Extensão de tríceps deitado', 'Deitado, flete os cotovelos levando a barra até à testa e estende sem abrir os braços.', 'Skull crusher', 'Lying down, bend the elbows to bring the bar to your forehead and extend without flaring.'),
    ('triceps-frances-halter', 'triceps', 'dumbbell', 'intermediate', 'Tríceps francês com halter', 'Halter acima da cabeça, desça atrás da nuca e estenda os cotovelos.', 'Extensão de tríceps acima da cabeça', 'Haltere acima da cabeça, desce atrás da nuca e estende os cotovelos.', 'Overhead dumbbell extension', 'With the dumbbell overhead, lower it behind your head and extend the elbows.'),
    ('mergulho-banco', 'triceps', 'bodyweight', 'beginner', 'Mergulho no banco', 'Mãos no banco atrás do corpo, desça flexionando os cotovelos a 90 graus.', 'Fundos no banco', 'Mãos no banco atrás do corpo, desce fletindo os cotovelos a 90 graus.', 'Bench dip', 'Hands on a bench behind you, lower until the elbows reach about 90 degrees.'),
    ('agachamento-livre', 'quadriceps', 'barbell', 'advanced', 'Agachamento livre', 'Barra nas costas, desça até a coxa passar da paralela mantendo os joelhos alinhados.', 'Agachamento com barra', 'Barra nas costas, desce até a coxa passar a paralela mantendo os joelhos alinhados.', 'Barbell back squat', 'With the bar on your back, squat below parallel keeping the knees tracking the toes.'),
    ('leg-press', 'quadriceps', 'machine', 'beginner', 'Leg press 45 graus', 'Pés na plataforma na largura dos ombros, desça até 90 graus sem tirar o quadril do apoio.', 'Prensa de pernas', 'Pés na plataforma à largura dos ombros, desce até 90 graus sem tirares a anca do apoio.', 'Leg press', 'With feet shoulder-width on the platform, lower to 90 degrees keeping the hips down.'),
    ('cadeira-extensora', 'quadriceps', 'machine', 'beginner', 'Cadeira extensora', 'Estenda os joelhos até quase travar e desça controlando o peso.', 'Extensão de pernas na máquina', 'Estende os joelhos até quase travar e desce controlando o peso.', 'Leg extension', 'Extend the knees to just short of lockout and lower the weight under control.'),
    ('afundo-halteres', 'quadriceps', 'dumbbell', 'intermediate', 'Afundo com halteres', 'Dê um passo à frente e desça até o joelho de trás quase tocar o chão.', 'Avanço com halteres', 'Dá um passo à frente e desce até o joelho de trás quase tocar o chão.', 'Dumbbell lunge', 'Step forward and lower until the back knee nearly touches the floor.'),
    ('agachamento-hack', 'quadriceps', 'machine', 'intermediate', 'Agachamento hack', 'Costas apoiadas na máquina, desça até a coxa ficar paralela à plataforma.', 'Agachamento na máquina hack', 'Costas apoiadas na máquina, desce até a coxa ficar paralela à plataforma.', 'Hack squat', 'With your back on the pad, descend until the thighs are parallel to the platform.'),
    ('mesa-flexora', 'hamstrings', 'machine', 'beginner', 'Mesa flexora', 'Deitado de bruços, flexione os joelhos levando o rolo em direção aos glúteos.', 'Flexão de pernas deitado', 'Deitado de barriga para baixo, flete os joelhos levando o rolo para os glúteos.', 'Lying leg curl', 'Lying face down, curl the pad toward your glutes.'),
    ('cadeira-flexora', 'hamstrings', 'machine', 'beginner', 'Cadeira flexora', 'Sentado, flexione os joelhos até o limite confortável e volte devagar.', 'Flexão de pernas sentado', 'Sentado, flete os joelhos até ao limite confortável e regressa devagar.', 'Seated leg curl', 'Seated, curl the knees as far as comfortable and return slowly.'),
    ('stiff-barra', 'hamstrings', 'barbell', 'intermediate', 'Stiff com barra', 'Joelhos semiflexionados, desça a barra rente às pernas empurrando o quadril para trás.', 'Peso morto de pernas esticadas', 'Joelhos semifletidos, desce a barra rente às pernas empurrando a anca para trás.', 'Romanian deadlift', 'With soft knees, lower the bar along your legs by pushing the hips back.'),
    ('elevacao-pelvica', 'glutes', 'barbell', 'intermediate', 'Elevação pélvica com barra', 'Costas apoiadas no banco, suba o quadril até o tronco ficar paralelo ao chão.', 'Elevação da anca com barra', 'Costas apoiadas no banco, sobe a anca até o tronco ficar paralelo ao chão.', 'Barbell hip thrust', 'With your back on a bench, drive the hips up until the torso is parallel to the floor.'),
    ('gluteo-polia', 'glutes', 'cable', 'beginner', 'Glúteo na polia', 'Preso ao tornozelo, leve a perna para trás contraindo o glúteo no final.', 'Extensão da anca na polia', 'Preso ao tornozelo, leva a perna para trás contraindo o glúteo no final.', 'Cable glute kickback', 'With the strap on your ankle, drive the leg back and squeeze the glute at the end.'),
    ('abducao-maquina', 'abductors', 'machine', 'beginner', 'Abdutora na máquina', 'Sentado, abra as pernas contra a resistência e volte controlando.', 'Abdutora na máquina', 'Sentado, abre as pernas contra a resistência e regressa controlando.', 'Hip abduction machine', 'Seated, push the legs apart against the resistance and return under control.'),
    ('panturrilha-em-pe', 'calves', 'machine', 'beginner', 'Panturrilha em pé', 'Suba na ponta dos pés até o limite e desça alongando a panturrilha.', 'Gémeos em pé na máquina', 'Sobe na ponta dos pés até ao limite e desce alongando os gémeos.', 'Standing calf raise', 'Rise onto the balls of your feet and lower to a full stretch.'),
    ('panturrilha-sentado', 'calves', 'machine', 'beginner', 'Panturrilha sentado', 'Joelhos a 90 graus, eleve os calcanhares e segure a contração no topo.', 'Gémeos sentado', 'Joelhos a 90 graus, eleva os calcanhares e segura a contração no topo.', 'Seated calf raise', 'With knees at 90 degrees, lift the heels and hold the contraction at the top.'),
    ('abdominal-supra', 'abs', 'bodyweight', 'beginner', 'Abdominal supra', 'Deitado com joelhos dobrados, eleve o tronco tirando as escápulas do chão.', 'Abdominal curto', 'Deitado com joelhos dobrados, eleva o tronco tirando as omoplatas do chão.', 'Crunch', 'Lying with knees bent, lift the torso until the shoulder blades leave the floor.'),
    ('prancha-isometrica', 'abs', 'bodyweight', 'beginner', 'Prancha isométrica', 'Apoiado nos antebraços, mantenha o corpo alinhado contraindo o abdômen.', 'Prancha', 'Apoiado nos antebraços, mantém o corpo alinhado contraindo o abdómen.', 'Plank', 'Resting on your forearms, hold the body in a straight line with the core braced.'),
    ('elevacao-pernas-suspenso', 'abs', 'bodyweight', 'intermediate', 'Elevação de pernas suspenso', 'Pendurado na barra, eleve as pernas até a altura do quadril sem balançar.', 'Elevação de pernas na barra', 'Suspenso na barra, eleva as pernas até à altura da anca sem balançares.', 'Hanging leg raise', 'Hanging from the bar, raise your legs to hip height without swinging.');

-- Nome canônico fica na língua-fonte (ADR-011 §1): é o fallback final da
-- leitura quando não há tradução para o locale pedido.
INSERT INTO exercises (id, tenant_id, name, primary_muscle, equipment, level, status)
SELECT id, NULL, name_pt_br, primary_muscle, equipment, level, 'active'
FROM seed_exercises
ON CONFLICT (id) DO UPDATE SET
    name           = EXCLUDED.name,
    primary_muscle = EXCLUDED.primary_muscle,
    equipment      = EXCLUDED.equipment,
    level          = EXCLUDED.level,
    updated_at     = now();

INSERT INTO exercise_translations (exercise_id, tenant_id, locale, name, instructions)
SELECT s.id, NULL, t.locale, t.name, t.instructions
FROM seed_exercises s
CROSS JOIN LATERAL (
    VALUES
        ('pt-BR', s.name_pt_br, s.instr_pt_br),
        ('pt-PT', s.name_pt_pt, s.instr_pt_pt),
        ('en',    s.name_en,    s.instr_en)
) AS t(locale, name, instructions)
ON CONFLICT (exercise_id, locale) DO UPDATE SET
    name         = EXCLUDED.name,
    instructions = EXCLUDED.instructions,
    updated_at   = now();

COMMIT;
