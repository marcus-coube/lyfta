# Roteiro E2E — P1 (Treino)

Fecha o marco da fase P1: **o coach monta o treino e o aluno executa offline,
com a rotação A→B→C andando sozinha.** É o roteiro do Aceite do P1.8 e o
teste de fumaça a rodar antes de cada release enquanto não houver E2E
automatizado.

Não substitui os testes de unidade e handler — cobre o que eles não alcançam:
dois clientes reais, duas plataformas e a rede caindo no meio.

## Pré-requisitos

| Item | Como |
|---|---|
| Postgres com os 4 bancos | `psql -U postgres -f backend/scripts/create-dbs.sql` |
| Redis + MinIO | `cd backend && docker compose up -d` |
| Seed da biblioteca | `psql -U postgres -d lyfta_workout -f backend/workout/seed/exercises_seed.sql` |
| `identity` no ar (8081) | `cd backend/identity && go run ./cmd/api` |
| `workout` no ar (8082) | `cd backend/workout && go run ./cmd/api` |
| Coach na web | `cd app && flutter run -d chrome` |
| Aluno em Android | emulador + `flutter run -d emulator-5554` com as `--dart-define` de `10.0.2.2` (ver [app/README.md](../../../app/README.md)) |

Convite chega por e-mail via Resend; em dev o `logMailer` imprime o link no log
do `identity` — é de lá que se copia o token.

## Roteiro

Cada passo diz **o que fazer** e **o que tem de acontecer**. Um passo que falha
interrompe o roteiro: anotar como bug nas "Notas de execução" do P1.

### 1. Conta e convite (coach, web)

1. `/signup`: criar a academia com um e-mail novo. → Entra logado como `owner`.
2. Alunos → convidar, com nome e e-mail do aluno. → Convite criado; o link
   aparece no log do `identity`.
3. Abrir o link do convite numa janela anônima e definir a senha. → O aluno
   entra e cai na tela Hoje, com "seu professor ainda não montou seu treino".

### 2. Biblioteca e plano A/B/C (coach, web)

4. Biblioteca: buscar um exercício do seed (ex.: "supino"). → Busca sem acento
   funciona e o GIF do exercício global carrega.
5. Criar um plano para o aluno com **três dias** (A, B, C), cada um com pelo
   menos um exercício e duas séries prescritas (reps e carga alvo).
6. Publicar. → Confirmação mostra a versão 1; o plano some do rascunho.

### 3. Treino do dia (aluno, Android)

7. Abrir o app do aluno e puxar para atualizar. → Tela Hoje mostra **Treino A**,
   com a prescrição de cada série.
8. Conferir o rodapé da rotação. → "Próximo: treino B".

### 4. Execução offline (aluno, Android)

9. **Ligar o modo avião** (`adb shell svc wifi disable && adb shell svc data disable`,
   ou pelo painel do emulador).
10. Iniciar o treino e registrar todas as séries do dia A, com carga diferente
    da prescrita em pelo menos uma. → Cada série registra na hora; o timer de
    descanso conta e avisa (som + vibração) mesmo sem rede.
11. Corrigir uma série já registrada. → A correção aparece; o histórico não
    perde o valor antigo (append-only, ADR-003 §2).
12. Encerrar o treino. → Resumo com total de séries e volume; o indicador mostra
    "N registros por enviar".
13. Fechar e reabrir o app **ainda offline**. → A fila continua lá e o treino do
    dia continua desenhando (cache do ADR-003 §3).

### 5. Sincronização e rotação (aluno, Android)

14. **Desligar o modo avião.** → O worker drena a fila sozinha em segundos; o
    indicador vai para "tudo sincronizado" e as pendências zeram.
15. Puxar para atualizar. → A tela Hoje agora mostra **Treino B**, e o rodapé
    "Próximo: treino C".
16. Conferir "últimos treinos". → Aparece o treino A com o total de séries e o
    volume **iguais** ao resumo visto offline no passo 12.

### 6. Troca de treino (aluno, Android)

17. "Trocar treino de hoje" → escolher o **C**. → A tela passa a mostrar o
    Treino C e o rodapé "Próximo: treino A" (o rodízio é circular).
18. Ligar o modo avião e tentar trocar de novo. → Mensagem de que trocar o
    treino precisa de internet; o dia na tela **não** muda.

### 7. Volta circular (aluno, Android)

19. Desligar o modo avião, executar e encerrar o treino C.
20. Atualizar a tela Hoje. → Mostra **Treino A**: o rodízio fechou a volta.

### 8. O coach enxerga (coach, web)

21. Na lista de alunos, abrir o aluno. → O plano ativo aparece com a versão
    publicada.
22. Republicar o plano (mexer numa carga e publicar de novo). → Vira versão 2 e
    o aluno **continua no mesmo rótulo** de dia, não volta para o A (P1.4).

## Registro da execução

| Data | Máquina | Coach | Aluno | Resultado |
|---|---|---|---|---|
| — | — | — | — | — |
