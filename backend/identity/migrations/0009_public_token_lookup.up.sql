-- Aceite de convite (POST /v1/invitations/accept) e redefinição de senha
-- (POST /v1/auth/reset-password) são endpoints PÚBLICOS: o cliente só tem o
-- token em mãos, ainda não sabe o tenant_id para setar app.tenant_id. Sem
-- isso, a policy tenant_isolation de invitations/password_resets compara
-- tenant_id a current_setting(...) = NULL e não retorna nenhuma linha —
-- mesma situação já resolvida em 0008_email_lookup para o login entre
-- tenants (ADR-002 §2b/2c).
--
-- Mesma solução: funções SQL SECURITY DEFINER, de propriedade do dono das
-- tabelas (não de lyfta_app), com superfície mínima — devolvem a linha
-- completa do convite/reset (não há coluna sensível nessas tabelas, ao
-- contrário de users.password_hash), mas só pelo hash exato do token, nunca
-- por listagem. lyfta_app recebe apenas EXECUTE, não SELECT direto fora do
-- tenant setado (ADR-001 §4: RLS é rede de segurança, o filtro explícito
-- continua obrigatório no restante do acesso a dados).
CREATE FUNCTION find_invitation_by_token(p_token_hash TEXT)
RETURNS TABLE (
    id UUID, tenant_id UUID, email TEXT, role TEXT, token_hash TEXT,
    invited_by UUID, expires_at TIMESTAMPTZ, accepted_at TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id, tenant_id, email, role, token_hash, invited_by, expires_at, accepted_at, created_at
    FROM invitations
    WHERE token_hash = p_token_hash AND accepted_at IS NULL AND expires_at > now();
$$;

REVOKE ALL ON FUNCTION find_invitation_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_invitation_by_token(TEXT) TO lyfta_app;

CREATE FUNCTION find_password_reset_by_token(p_token_hash TEXT)
RETURNS TABLE (
    id UUID, user_id UUID, tenant_id UUID, token_hash TEXT,
    expires_at TIMESTAMPTZ, used_at TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id, user_id, tenant_id, token_hash, expires_at, used_at, created_at
    FROM password_resets
    WHERE token_hash = p_token_hash AND used_at IS NULL AND expires_at > now();
$$;

REVOKE ALL ON FUNCTION find_password_reset_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_password_reset_by_token(TEXT) TO lyfta_app;
