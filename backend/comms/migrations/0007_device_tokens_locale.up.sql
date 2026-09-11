-- device_tokens.locale: idioma do destinatário no momento do registro do
-- device (P3.4, POST /v1/devices) — é a única fonte do locale de quem VAI
-- RECEBER um push fora de uma requisição HTTP dele: o job diário de "treino
-- pendente" roda numa goroutine (sem claim JWT), e mesmo nos eventos em
-- tempo real (message.new, checkin.pain_strong) as claims disponíveis no
-- request são as de quem DISPARA o evento (remetente/aluno), nunca as do
-- destinatário. Renderizar o push sempre a partir desta coluna, para os dois
-- casos, mantém uma única fonte de verdade em vez de dois caminhos
-- divergentes (ver Notas de execução do P3-comunicacao.md).
ALTER TABLE device_tokens ADD COLUMN locale TEXT NOT NULL DEFAULT 'pt-BR';
