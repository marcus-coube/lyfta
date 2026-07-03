# ADR-008 — LGPD: dados de saúde são dados sensíveis

**Status:** Aceito
**Data:** 2026-07-02

## Contexto

O Lyfta armazena lesões, avaliações físicas (peso, % de gordura, circunferências),
fotos de progresso e, no running, dados de frequência cardíaca e localização.
Sob a LGPD (art. 5º, II), dados referentes à saúde são **dados pessoais sensíveis** e
exigem base legal específica — na prática, consentimento explícito e destacado.
Isto é requisito de MVP, não de futuro.

## Decisão

1. **Consentimento explícito e granular no onboarding do aluno**, registrado em
   `consents (user_id, purpose, granted_at, revoked_at, version_do_termo)`:
   separar (a) dados de saúde para prescrição de treino, (b) fotos de progresso,
   (c) localização/GPS (quando o running chegar).
2. **Direito de eliminação (art. 18):** implementar desde o MVP um fluxo de exclusão de
   conta que apaga/anonimiza dados pessoais do aluno. Regras:
   - Dados de saúde e fotos: exclusão física.
   - Registros financeiros: anonimização do titular, mantendo o registro contábil
     (obrigação legal de guarda).
   - Execuções de treino: anonimizar (viram estatística sem titular) ou excluir.
3. **Minimização de acesso:** coach só vê dados de saúde dos alunos vinculados a ele;
   Reception não vê dados de saúde (refinar no doc de permissões).
4. **Fotos de progresso:** bucket privado, URLs assinadas com expiração curta, nunca
   públicas.
5. **Criptografia:** TLS em trânsito; disco criptografado no VPS; backups criptografados.
6. Documento de privacidade + termos exibidos no onboarding, versionados no repo.

## Consequências

- Onboarding do aluno ganha uma etapa obrigatória de consentimento.
- Exclusão de conta precisa ser testada como feature de primeira classe.
- Vender para academias fica mais fácil: conformidade LGPD é argumento comercial.
