# Roteiro E2E final — MVP 1.0

Roteiro do passo 1 da P4.4: professor na web e aluno em Android, iOS e Flutter
Web, do signup ao calendário. Estende o [e2e-p1.md](e2e-p1.md) (treino
offline), que continua valendo como sub-roteiro dos passos 6 a 11.
Um passo que falha interrompe o roteiro: anotar o bug nas Notas da P4.

## Pré-requisitos

| Item | Como |
|---|---|
| Bancos, Redis, MinIO, seed | iguais ao [e2e-p1.md](e2e-p1.md) |
| 4 serviços no ar | identity 8081, workout 8082, assessment 8083, comms 8084 |
| E-mail de convite | **staging com `RESEND_API_KEY` real** (falta). Em dev, `logMailer` imprime o link no log do `identity` |
| Push | `google-services.json` no Android, `GoogleService-Info.plist` + APNs no iOS, `FCM_CREDENTIALS_JSON` no `comms`, AVD com Play Store ou aparelho físico |
| Professor | `cd app && flutter run -d chrome` (ou o build `app/build/web` servido) |
| Aluno Android | `flutter run -d <device>` com `--dart-define` apontando os 4 serviços (`10.0.2.2` no emulador; ver app/README.md) |
| Aluno iOS | simulador iPhone 17, receita em app/README.md § iOS. Push não funciona no simulador sem APNs |
| Aluno Web | segunda janela anônima do Chrome |

## Roteiro (executar uma vez por plataforma de aluno)

### 1. Conta e convite (professor, web)
1. `/signup` com e-mail novo. Entra logado como `owner`.
2. Alunos, convidar com nome e e-mail. Convite chega por e-mail (staging) ou no log.
3. Aluno abre o link, **vê e aceita o termo de consentimento** (ADR-008; hoje
   inexistente, ver LGPD nas Notas da P4) e define a senha. Cai em Hoje.

### 2. Plano (professor, web)
4. Biblioteca: buscar "supino" (sem acento). GIF carrega.
5. Criar plano A/B/C com 2 séries prescritas por dia e publicar (versão 1).

### 3. Treino offline e sync (aluno)
6. Hoje mostra Treino A com a prescrição.
7. Modo avião. Executar o treino registrando cargas, corrigir uma série,
   encerrar. Indicador mostra "N registros por enviar". Reabrir o app offline:
   fila preservada. (Na web não há fila persistente em disco: só testar
   offline em Android/iOS.)
8. Voltar a rede. Fila drena sozinha; Hoje passa a B.

### 4. Evolução (aluno)
9. Aba Evolução: gráfico de carga reflete o treino do passo 7.
10. Registrar medidas e bioimpedância; enviar foto. Deltas e comparador aparecem.
11. Professor abre a ficha do aluno: vê o mesmo gráfico, medidas, fotos e a aba Resumo.

### 5. Chat e push (aluno e professor)
12. Aluno envia texto e imagem. Professor recebe pelo WS sem recarregar.
13. **Fechar o app do aluno.** Professor responde: push chega; tocar abre a conversa.
14. Aluno com treino pendente no dia: push "treino pendente" chega uma única vez.

### 6. Check-in (aluno e professor)
15. Ao encerrar um treino, bottom sheet de check-in; enviar com nota.
    Sem rede: rascunho local e reenvio depois.
16. Professor: aba Check-ins mostra o item com badge de não revisado; revisar zera o badge.

### 7. Agenda (aluno)
17. Aba Agenda: strip da semana marca o dia treinado (feito), projeta os
    próximos (previsto) e dias passados sem treino como descanso.
18. Navegar entre semanas, expandir o mês, conferir o streak.

### 8. Conta e dados (LGPD)
19. **Excluir conta** pelo app: dados de saúde e fotos removidos fisicamente
    (ADR-008). Inexistente hoje: bloqueia release.

## Checklist de smoke por plataforma

Rodar antes de cada release, em cada alvo. Marcar com data.

| # | Verificação | Android | iOS | Web |
|---|---|---|---|---|
| 1 | App abre sem tela vermelha; login com conta existente | ✅ 11-07 | ✅ 11-07 | ✅ 11-07 |
| 2 | Signup do professor e aceite de convite (com consentimento) | ✅ 11-07 | ⬜ | ✅ 11-07 (professor) |
| 3 | Hoje carrega treino; skeleton some | ✅ 11-07 | ⬜ | ✅ 11-07 |
| 4 | Executar treino, timer de descanso, correção, encerrar | ✅ 11-07 | ⬜ | ⬜ |
| 5 | Offline: executar, reabrir, sincronizar (só mobile) | ✅ 11-07 | ⬜ | n/a |
| 6 | Evolução: gráfico, medidas, bioimp, foto | ✅ 11-07 | ⬜ | ✅ 11-07 (professor) |
| 7 | Chat: texto, imagem, WS reconecta após queda | ✅ 11-07 | ⬜ | ✅ 11-07 (professor) |
| 8 | Push com app fechado abre o destino | pré-loja (L1) | pré-loja (L3) | n/a |
| 9 | Check-in enviado e visto pelo professor | ✅ 11-07 | ⬜ | ✅ 11-07 (professor) |
| 10 | Agenda: semana, mês, streak | ✅ 11-07 (mês corrigido) | ⬜ | ⬜ |
| 11 | Idiomas pt-BR, pt-PT e en trocam sem string crua | ✅ pt-BR | ✅ pt-BR (gate) | ✅ en |
| 12 | Logout e relogin; refresh de sessão após reabrir | ✅ 11-07 | ⬜ | ⬜ |
| 13 | Exclusão de conta (quando implementada) | ✅ 11-07 | ⬜ | ⬜ |

## Registro da execução

| Data | Plataforma do aluno | Resultado |
|---|---|---|
| 2026-11-07 | Android (emulador `lyfta_pixel`, pt-BR, `adb reverse` + modo avião) | **Passos 1–12 e 15–19 verdes** (13–14 push = pré-loja L1). Professor na web (en). 5 defeitos corrigidos no caminho — ver Notas da P4.4 |
| 2026-11-07 | iOS (simulador iPhone 17) | **Parcial**: app abre em pt-BR e o gate de consentimento funciona; roteiro interrompido — o simulador passou a levar até 15 min por ação |
| 2026-11-07 | Web (aluno) | **Parcial**: aceite de convite com consentimento ok; roteiro interrompido — painel do navegador oculto não renderiza |
