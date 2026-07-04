-- Login (POST /v1/auth/login) precisa localizar o(s) tenant(s) de um e-mail
-- ANTES de saber qual app.tenant_id setar (ADR-002 §2b/2c: lookup por e-mail
-- entre tenants; N matches -> tela de escolha). Com RLS forçada (ADR-001) e a
-- policy tenant_isolation de `users`, uma query sem app.tenant_id setado casa
-- contra current_setting(...) = NULL e não retorna nenhuma linha (validado
-- manualmente: `lyfta_app` sem tenant setado vê 0 linhas mesmo com dados
-- existentes) — ou seja, RLS bloqueia o próprio caso de uso que o login
-- precisa resolver antes da autenticação.
--
-- Solução adotada: uma única função SQL, de propriedade do dono das tabelas
-- (não de `lyfta_app`), com SECURITY DEFINER — roda com os privilégios do
-- dono e portanto ignora RLS, mas está estritamente limitada a devolver
-- (user_id, tenant_id, tenant_name) para um e-mail exato. Nunca expõe
-- password_hash nem qualquer outra coluna. `lyfta_app` recebe apenas EXECUTE
-- nesta função, não SELECT direto sobre `users` fora do tenant setado — o
-- resto do modelo de RLS continua intacto (ADR-001 §4: RLS é rede de
-- segurança, o filtro explícito nas demais queries continua obrigatório).
CREATE FUNCTION find_tenants_by_email(p_email TEXT)
RETURNS TABLE (user_id UUID, tenant_id UUID, tenant_name TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id, u.tenant_id, t.name
    FROM users u
    JOIN tenants t ON t.id = u.tenant_id
    WHERE u.email = p_email AND u.status = 'active';
$$;

REVOKE ALL ON FUNCTION find_tenants_by_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_tenants_by_email(TEXT) TO lyfta_app;
