package mail

import "fmt"

// InvitationMessage monta o e-mail de convite (P0.4 passo 2/5) — HTML inline
// simples, pt-BR (conteúdo de servidor, não string de UI do cliente —
// ADR-011 trata i18n de UI, não e-mail transacional).
func InvitationMessage(to, appURL, token, tenantName string) Message {
	link := fmt.Sprintf("%s/#/invite?token=%s", appURL, token)
	html := fmt.Sprintf(`
		<div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
			<h2>Você foi convidado para o Lyfta</h2>
			<p><strong>%s</strong> te convidou para fazer parte do Lyfta.</p>
			<p><a href="%s" style="display:inline-block;padding:10px 20px;background:#4f46e5;color:#fff;border-radius:6px;text-decoration:none;">Aceitar convite</a></p>
			<p>Ou copie e cole este link no navegador:<br>%s</p>
			<p style="color:#888;font-size:12px;">Este convite expira em 7 dias.</p>
		</div>`, tenantName, link, link)
	return Message{To: to, Subject: "Você foi convidado para o Lyfta", HTML: html}
}

// PasswordResetMessage monta o e-mail de recuperação de senha (P0.4 passo 4).
func PasswordResetMessage(to, appURL, token string) Message {
	link := fmt.Sprintf("%s/#/reset-password?token=%s", appURL, token)
	html := fmt.Sprintf(`
		<div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
			<h2>Redefinir sua senha no Lyfta</h2>
			<p>Recebemos um pedido para redefinir sua senha.</p>
			<p><a href="%s" style="display:inline-block;padding:10px 20px;background:#4f46e5;color:#fff;border-radius:6px;text-decoration:none;">Redefinir senha</a></p>
			<p>Ou copie e cole este link no navegador:<br>%s</p>
			<p style="color:#888;font-size:12px;">Este link expira em 1 hora. Se você não pediu, ignore este e-mail.</p>
		</div>`, link, link)
	return Message{To: to, Subject: "Redefinir sua senha no Lyfta", HTML: html}
}
