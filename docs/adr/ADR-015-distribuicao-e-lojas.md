# ADR-015 — Distribuição: validação por build direto; loja é etapa opcional

**Status:** Aceito
**Data:** 2026-09-11

## Contexto

O cliente valida **APK e IPA** antes de qualquer publicação. Nessa janela o nome
do produto ainda pode mudar, e com ele o identificador do app
(`applicationId` Android / bundle ID iOS — hoje `br.com.lyfta.lyfta`).

O identificador é de mão única depois do primeiro upload:

- **Play Console:** o package fica reservado na conta **para sempre** assim que
  um bundle é enviado — mesmo apagando o rascunho do app, ele não volta a ficar
  livre nem pode ser renomeado.
- **App Store Connect:** criar o app com um bundle ID prende os dois um ao
  outro; TestFlight exige essa criação.

Fora da loja, nada disso acontece: APK por link direto, Firebase App
Distribution e IPA ad-hoc distribuem builds sem registrar identificador em
lugar nenhum.

Some-se o alvo primeiro do produto: a web (ADR-005) e o app instalável cobrem o
mesmo escopo, e o aluno chega ao produto sem depender de loja. Publicar não é
pré-requisito de ninguém usar o Lyfta.

## Decisão

1. **Validação do cliente é sempre por build direto** — Android via APK
   (link direto ou Firebase App Distribution), iOS via ad-hoc (UDIDs dos
   aparelhos do cliente) ou App Distribution. **Nenhum upload em Play Console
   ou App Store Connect** antes do aceite do APK pelo cliente.
2. **Publicar em loja é um step opcional**, disparado à mão, nunca parte do
   pipeline de release e nunca automático no CI. O release padrão entrega a web
   no ar e os artefatos assinados (APK/AAB/IPA) — a loja é um destino a mais
   para esses mesmos artefatos, decidido caso a caso.
3. **O identificador é provisório até o aceite.** `br.com.lyfta.lyfta` só
   congela no primeiro upload em loja; antes disso trocá-lo é trabalho de
   minutos e está documentado em `app/README.md` (§ Firebase).
4. **Antes do primeiro upload**, e só então: nome/marca fechados, ícone e
   splash definitivos, política de privacidade publicada (ADR-008), conta
   Apple Developer ativa, keystore de release + Play App Signing, e o
   formulário de segurança de dados de cada loja.

## Consequências

- O CI não ganha job de publicação agora — o que não existe não publica por
  engano. Quando existir, nasce com disparo manual.
- A rodada de validação não queima o identificador: o cliente pode reprovar o
  nome sem custo de plataforma.
- Trocar o identificador depois do aceite e antes da loja custa: duas linhas em
  `app/android/app/build.gradle.kts`, o pacote/pasta do `MainActivity.kt`, a
  receita de `flutter create` do `app/README.md`, um app novo no mesmo projeto
  Firebase (`google-services.json` novo) e os tokens FCM já emitidos, que
  morrem na reinstalação. iOS custa zero enquanto `app/ios/` for gerado sob
  demanda (ADR-014).
- Distribuir IPA para validação **ainda exige conta Apple Developer paga**: é a
  assinatura que permite instalar, não a loja. Android não tem esse custo.
- O canal de validação vira parte do checklist de release, ao lado do roteiro
  E2E (`docs/plan/mvp1/e2e-p1.md`).
