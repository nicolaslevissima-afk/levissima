-- LEVÍSSIMA · 0041: PCP e Produção (pedido de 03/11/2026).
-- * producao-eventos: iniciar, pausar e retomar a OP (um documento por evento, só inclusão — o líder de produção, que
--   entra "só inclui", também consegue). Fica junto das coleções da produção: só a senha mestre e o escritório
--   (equipe) leem e gravam; motorista, representante e setor não veem.
create or replace function public.colecao_producao(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('producao-ordens', 'producao-eventos', 'mp-insumos', 'mp-fichas', 'mp-movs', 'garrafoes-fechamentos', 'mp-config'); $$;
