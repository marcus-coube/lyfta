# Plano de execução — MVP 2.5

Pacote intermediário, fora do roadmap do [doc 000](../../000-product_description.md):
**ajustes da validação do 2.0 com o cliente** (2026-11-13). Não antecipa nada do
3.0. Mesmo modo de execução do [MVP 2.0](../mvp2/README.md): **uma tarefa por
vez** pelo agente `mvp-dev`, com supervisão humana. A numeração continua (P9 em
diante).

## Origem → tarefa

| Pedido do cliente | Tarefa |
|---|---|
| Professor: "Cluster set" como tipo de bloco | P9.1, P9.3, P9.4 |
| Professor: rótulo opcional por série, chip colorido no treino | P9.1, P9.3, P9.4 |
| Professor: CRUD "Variações" (nome + descrição), por série, chip + (i) no treino | P9.2, P9.3, P9.4 |
| Professor: check-in com métricas do treino, qual treino foi feito, exercícios e cargas ao abrir | P11.1, P11.2 |
| Aluno: "replicar" a carga para as outras séries do exercício | P10.1 |
| Aluno: modal de treino concluído ao fechar a última série, com voltar | P10.2 |
| Aluno: cronômetro geral do treino, nas métricas finais e no check-in do professor | P10.2, P11.1, P11.2 |
| Aluno: anexar mídia (≤ 20 MB) durante o treino, apagada 7 dias após o professor ver/responder | P12.1–P12.3 |

## Escopo

| Entra | Fica fora |
|---|---|
| `cluster` como sexto `block_type` ([ADR-019](../../adr/ADR-019-prescricao-cluster-rotulo-variacao.md)) | Mini-séries modeladas por campo próprio (reps por mini-série, pausa intra-série) |
| Rótulo livre e variação por série, copiados para o snapshot | Tradução de rótulo/variação (conteúdo do tenant, um idioma) |
| Detalhe da sessão para o coach (exercícios, cargas, duração) | Coach editar/comentar série a série; fila global de check-ins |
| Replicar carga, modal de conclusão, cronômetro geral | Desfazer série registrada (evento de anulação — exigiria mexer no ADR-003); pausar o cronômetro |
| Mídia de execução com retenção ([ADR-020](../../adr/ADR-020-midia-de-execucao-retencao.md)) | Upload offline em fila; anotação/desenho sobre o vídeo; mídia fora de uma sessão |

## Fases

| Fase | Arquivo | Entrega |
|---|---|---|
| P9 | [P9-prescricao.md](P9-prescricao.md) | Cluster set, rótulo por série, Variações (servidor, builder e player) |
| P10 | [P10-player.md](P10-player.md) | Replicar carga, cronômetro geral, modal de treino concluído |
| P11 | [P11-checkin-coach.md](P11-checkin-coach.md) | Sessão do aluno para o coach; check-in com métricas e detalhe |
| P12 | [P12-midia-execucao.md](P12-midia-execucao.md) | Mídia de execução (comms + app dos dois lados), E2E e release 2.5.0 |

Ordem P9→P12. P10 é só app e independe da P9 (pode ser adiantada). P11.2 usa a
duração da P10.2 só para exibição (o dado já existe no servidor). P12.3 encaixa
na tela da P11.2.

Progresso agregado: [STATUS.md](STATUS.md). Fonte de verdade do progresso: os
checkboxes nos arquivos de fase.

## Decisões a confirmar (antes da tarefa indicada)

**Todas confirmadas pelo usuário em 2026-11-13, na opção recomendada** (registro
no [STATUS](STATUS.md)). Mudou a decisão → ajustar a tarefa e o ADR antes de
implementar.

| # | Decisão | Recomendado (escrito no plano) | Alternativa | Trava |
|---|---|---|---|---|
| D1 | Como modelar o cluster | Igual a dropset/rest-pause hoje: só o tipo; cada mini-série é uma série prescrita com descanso curto | Série = cluster inteiro, com campos novos (nº de mini-séries, pausa) e uma linha de registro por cluster | P9.1 |
| D2 | Rótulo da série | Texto livre (até 24), com sugestões no builder; uma cor de chip para rótulo, outra para variação | Lista fixa traduzida (aquecimento, top set, back-off…) com cor por item | P9.1 |
| D3 | "Voltar" no modal de conclusão | Fecha o modal e mantém a sessão aberta; série errada se **corrige** (revisão), não se desmarca | Criar evento de anulação de série (novo ADR sobre o ADR-003) | P10.2 |
| D4 | Vídeo de 20 MB | Comprimir no celular antes de enviar (dependência nova `video_compress`); web só valida o tamanho | Sem compressão: 20 MB ≈ 10–15 s de vídeo 1080p de celular; a maioria dos anexos seria recusada | P12.2 |
| D5 | Professor nunca abre a mídia | Teto de 30 dias desde o envio, apaga mesmo sem visualização | Fica até o professor ver (armazenamento sem limite) | P12.1 |
| D6 | Consentimento da mídia | Reusa a finalidade `progress_photos` (imagem do aluno); texto dos termos ganha a regra de retenção, `TERMS_VERSION` novo | Finalidade nova `execution_media` com tela de aceite própria | P12.1 |
| D7 | "Respondido" | Professor marca **Visto** ou escreve um retorno; o retorno vira mensagem no chat direto com o aluno (push de graça) | Thread de comentários própria na mídia | P12.1 |

## Protocolo do agente

O mesmo do [README do 1.0](../mvp1/README.md#protocolo-do-agente-obrigatório),
trocando os caminhos: ler este README e o arquivo da fase; registrar em
`docs/plan/mvp25/STATUS.md`; commit `feat(p9.1): ...`. Sem ID explícito, pegar a
primeira tarefa não marcada na ordem P9→P12. Tarefa com decisão D* ainda não
confirmada no STATUS → **parar e reportar**.

## Regras transversais (além das do 1.0 e do 2.0)

- **Contrato pode quebrar:** ninguém usa o app; campo novo entra no lugar certo,
  sem camada de compatibilidade.
- **Snapshot (ADR-004):** tudo que o aluno vê da prescrição (rótulo, nome e
  descrição da variação) é **copiado** para `/me/today` e para o snapshot da
  sessão. Editar ou arquivar uma variação não muda treino já publicado.
- **Offline (ADR-003) inalterado:** nenhum tipo de evento novo, nenhum campo
  novo em `set_log`. Mídia de execução exige rede e fica fora da fila (ADR-020).
- **Métricas do treino têm uma definição só** (séries, reps, volume, duração —
  P10.2) usada no resumo do aluno e no check-in do coach.
- **Vínculo (ADR-016):** rotas novas de coach sobre aluno passam pelo
  `coachlink`.
