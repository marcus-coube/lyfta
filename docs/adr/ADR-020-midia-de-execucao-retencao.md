# ADR-020 — Mídia de execução: dono, retenção e offline

**Status:** Aceito (D4–D7 do [plano do 2.5](../plan/mvp25/README.md) confirmadas em 2026-11-13)
**Data:** 2026-11-13

## Contexto

O cliente pediu que o aluno anexe mídia (até 20 MB) durante o treino para o
professor avaliar o movimento, com exclusão 7 dias depois que o professor
visualizar ou responder. É vídeo do corpo do aluno (dado pessoal, ADR-008), o
primeiro objeto do sistema com **prazo de vida**, e nasce dentro da única área
offline do app (ADR-003).

## Decisão

1. **Dono: `comms`.** A mídia é chaveada por `session_client_id`, como o
   check-in, e a ciência/resposta do professor é comunicação. O `workout` não
   sabe que ela existe.
2. **Limites:** 20 MB por arquivo (na assinatura do presign e conferido no
   registro), vídeo ou imagem, até 3 por sessão. Bucket privado, leitura só por
   URL assinada curta.
3. **Retenção:** o professor dá ciência **uma vez** (marcar como visto ou
   responder); a mídia é apagada **7 dias depois**. Sem ciência, é apagada
   **30 dias** após o envio. Um job do `comms` apaga o objeto e mantém a linha
   sem a chave. O aluno é avisado da regra antes de enviar, e o professor antes
   de dar ciência. O aluno pode retirar a mídia a qualquer momento.
4. **Resposta do professor = mensagem no chat direto** com o aluno, publicada
   pelo próprio `comms`. Não há thread própria da mídia.
5. **Consentimento:** exige a finalidade `progress_photos` (imagem do aluno);
   os termos descrevem a mídia de execução e a retenção (nova versão do termo).
   Exclusão de conta apaga fisicamente objetos e linhas.
6. **Offline:** anexar **exige rede** e **não** entra na fila de eventos do
   ADR-003. O escopo offline continua sendo só a execução.

## Consequências

- Primeiro job de expiração e primeira exclusão física de objeto no `comms`;
  as imagens do chat e a mídia de exercício seguem sem expiração.
- Aluno treinando sem rede não anexa; aceito para não abrir fila de upload de
  arquivo grande em segundo plano.
- 20 MB cobre poucos segundos de vídeo bruto de celular: o app comprime antes
  de enviar (dependência nova, D4). Sem isso o limite inviabiliza o recurso.
- A resposta fica no chat depois que a mídia expira; quem lê depois não vê mais
  o vídeo — a mensagem cita treino e exercício.
- **Alternativa rejeitada:** guardar a mídia no `workout` ligada à sessão.
  Obrigaria o `workout` a ter estado de revisão, push e chamada ao chat.
