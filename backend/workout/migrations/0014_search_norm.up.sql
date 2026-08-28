-- Normalização de texto para busca da biblioteca (P1.3): minúsculas + sem
-- acento. O aluno/professor digita "triceps" e precisa achar "Tríceps".
--
-- Feita com translate() em vez da extensão `unaccent` de propósito: extensão
-- exige superusuário para instalar (dev, CI e produção gerenciada), e
-- unaccent() é STABLE — não indexável sem wrapper. Esta é IMMUTABLE, roda em
-- qualquer Postgres e cobre o acento que o português usa.
CREATE OR REPLACE FUNCTION lyfta_search_norm(input TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
    SELECT translate(
        lower(input),
        'áàâãäéèêëíìîïóòôõöúùûüçñý',
        'aaaaaeeeeiiiiooooouuuucny'
    );
$$;

-- A 0013 concedeu EXECUTE nas funções que existiam até ela; esta nasceu
-- depois.
GRANT EXECUTE ON FUNCTION lyfta_search_norm(TEXT) TO lyfta_app;
