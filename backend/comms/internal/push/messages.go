package push

// texts é a tabela de tradução do push — o servidor renderiza (ADR-011 §3),
// então as chaves vivem aqui, não em ARB do Flutter (que é só string de UI
// do app). Cobre os três locales do lançamento (ADR-011 §1) para os três
// tipos de notificação do MVP (ADR-012).
var texts = map[Kind]map[string]struct{ Title, Body string }{
	KindMessageNew: {
		"pt-BR": {Title: "Nova mensagem", Body: "Você recebeu uma nova mensagem."},
		"pt-PT": {Title: "Nova mensagem", Body: "Recebeu uma nova mensagem."},
		"en":    {Title: "New message", Body: "You have a new message."},
	},
	KindCheckinPainStrong: {
		"pt-BR": {Title: "Alerta de dor", Body: "Um aluno relatou dor forte no treino."},
		"pt-PT": {Title: "Alerta de dor", Body: "Um aluno relatou dor forte no treino."},
		"en":    {Title: "Pain alert", Body: "A student reported strong pain during training."},
	},
	KindWorkoutPending: {
		"pt-BR": {Title: "Treino pendente", Body: "Seu treino de hoje te espera."},
		"pt-PT": {Title: "Treino pendente", Body: "O seu treino de hoje espera por si."},
		"en":    {Title: "Workout pending", Body: "Your workout today is waiting for you."},
	},
}

// renderText devolve título/corpo de um tipo de notificação no locale
// informado, com pt-BR (a língua-fonte, ADR-011 §1) como fallback para
// qualquer locale que não seja um dos três conhecidos — nunca manda um push
// vazio por causa de um dado inesperado numa coluna que hoje só aceita os
// três valores, mas não é validado por CHECK constraint.
func renderText(kind Kind, locale string) (title, body string) {
	byLocale, ok := texts[kind]
	if !ok {
		return "", ""
	}
	if t, ok := byLocale[locale]; ok {
		return t.Title, t.Body
	}
	t := byLocale["pt-BR"]
	return t.Title, t.Body
}
