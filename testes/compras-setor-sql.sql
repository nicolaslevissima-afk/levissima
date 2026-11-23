-- LEVÍSSIMA · teste da 0063 (Compras: cada um vê só o seu setor ou os próprios pedidos). Banco local mínimo.
-- Rodar: createdb t && psql -d t -f testes/compras-setor-sql.sql   (aplica a 0063 no meio)
\set ON_ERROR_STOP 1
create schema if not exists auth;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table public.docs (colecao text not null, id text not null, data jsonb not null default '{}'::jsonb, atualizado_em timestamptz not null default now(), primary key (colecao, id));
create function public.papel_atual() returns text language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') $$;
create function public.ref_atual() returns text language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'ref', '') $$;
create function public.sem_acento_0009(t text) returns text language sql immutable as $f$ select lower(regexp_replace(btrim(translate(coalesce(t, ''), 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc')), '\s+', ' ', 'g')); $f$;
create function public.oc_funcoes_0046(m jsonb) returns text[] language sql immutable as $f$
  select array_remove(array[
    case when coalesce(m ->> 'cargo', '') in ('diretor', 'gerente', 'coordenador', 'supervisor', 'executiva', 'analista', 'assistente', 'lider', 'operador', 'outro') then m ->> 'cargo'
         when m ->> 'cargo' = 'executiva_comercial' then 'executiva' else 'sem-cargo' end,
    case when m -> 'coordenador' = 'true'::jsonb then 'marca:coordenador' end,
    case when m -> 'compras' = 'true'::jsonb then 'marca:compras' end,
    case when m -> 'aprovaCompra' = 'true'::jsonb then 'marca:aprovaCompra' end], null) $f$;
create function public.oc_pode_etapa_0046(m jsonb, p_etapa text) returns boolean language plpgsql stable as $f$
declare cfg jsonb; lista text[];
begin
  if m is null then return false; end if;
  select data -> 'etapas' -> p_etapa into cfg from public.docs where colecao = 'compras-config' and id = 'permissoes';
  select coalesce(array_agg(x), '{}') into lista from jsonb_array_elements_text(coalesce(cfg, '[]')) as x;
  return public.oc_funcoes_0046(m) && lista;
end $f$;
insert into public.docs values ('compras-config', 'permissoes', '{"etapas":{"coord":["gerente","coordenador","supervisor","marca:coordenador"],"compra":["diretor","marca:compras","marca:aprovaCompra"],"cotacao":["marca:compras"],"entrega":[],"revisao":[],"aprovacao":["diretor","marca:aprovaCompra"],"conferencia":["diretor","gerente","coordenador","supervisor","marca:compras","marca:aprovaCompra"],"recebimento":["diretor","coordenador","supervisor","analista","lider","sem-cargo","gerente"],"justificativa":[]}}');
insert into public.docs values
 ('equipe', 'gerente-q', '{"nome":"Gerente Q","cargo":"gerente","area":"Qualidade","setores":""}'),
 ('equipe', 'super-m', '{"nome":"Supervisor M","cargo":"supervisor","area":"Manutenção","setores":"","coordenador":true}'),
 ('equipe', 'coord-log', '{"nome":"Coord Log","cargo":"","area":"Logística","setores":"Logística, Expedição","coordenador":true}'),
 ('equipe', 'analista-p', '{"nome":"Analista P","cargo":"analista","area":"Produção"}'),
 ('equipe', 'lider-p', '{"nome":"Líder P","cargo":"lider","area":"Produção"}'),
 ('equipe', 'compras-a', '{"nome":"Compras A","cargo":"assistente","area":"Compras","compras":true}'),
 ('equipe', 'dir-f', '{"nome":"Diretora F","cargo":"diretor","area":"Financeiro"}'),
 ('equipe', 'sub-q', '{"nome":"Substituto Q","cargo":"analista","area":"Qualidade"}');
insert into public.docs values
 ('compras-ordens', 'o1', '{"status":"pedido","setor":"Expedição","pedido":{"id":"lider-p","ref":"escritorio:lider-p"}}'),
 ('compras-ordens', 'o2', '{"status":"pedido","setor":"Qualidade","pedido":{"id":"sub-q","ref":"escritorio:sub-q"}}'),
 ('compras-ordens', 'o3', '{"status":"comprado","setor":"Produção","pedido":{"id":"analista-p","ref":"escritorio:analista-p"}}'),
 ('compras-ordens', 'o4', '{"status":"recebido","setor":"Manutenção","pedido":{"id":"super-m","ref":"escritorio:super-m"},"recebimento":{"id":"lider-p"}}'),
 ('compras-ordens', 'o5', '{"status":"cotacao","setor":"Produção","pedido":{"id":"analista-p","ref":"escritorio:analista-p"},"coord":{"id":"super-m"}}'),
 ('compras-ordens', 'o6', '{"status":"pedido","setor":"Manutenção","pedido":{"id":"lider-p","ref":"escritorio:lider-p"}}');
\i supabase/migrations/0063_compras_ve_so_o_setor.sql
create function pg_temp.ve(p_ref text) returns text language plpgsql as $f$
declare out text;
begin
  perform set_config('request.jwt.claims', json_build_object('app_metadata', json_build_object('papel', case when p_ref = 'mestre' then 'mestre' else 'equipe' end, 'ref', p_ref))::text, true);
  select coalesce(string_agg(id, ',' order by id), '') into out from public.docs where colecao = 'compras-ordens' and public.oc_visivel_0025(data);
  return out;
end $f$;
do $t$
begin
  assert pg_temp.ve('mestre') = 'o1,o2,o3,o4,o5,o6', 'mestre vê tudo';
  assert pg_temp.ve('escritorio:gerente-q') = 'o2', 'gerente da Qualidade: só a Qualidade (antes via também o1 e o6 esperando autorização): ' || pg_temp.ve('escritorio:gerente-q');
  assert pg_temp.ve('escritorio:super-m') = 'o4,o5,o6', 'supervisor da Manutenção: Manutenção, o próprio e o que autorizou: ' || pg_temp.ve('escritorio:super-m');
  assert pg_temp.ve('escritorio:coord-log') = 'o1', 'coordenador com setores marcados (Logística, Expedição): ' || pg_temp.ve('escritorio:coord-log');
  assert pg_temp.ve('escritorio:analista-p') = 'o3,o5', 'analista: só os próprios pedidos: ' || pg_temp.ve('escritorio:analista-p');
  assert pg_temp.ve('escritorio:lider-p') = 'o1,o6', 'líder: só os próprios (o recebido que assinou de outro não): ' || pg_temp.ve('escritorio:lider-p');
  assert pg_temp.ve('escritorio:compras-a') = 'o1,o2,o3,o4,o5,o6', 'Compras vê tudo';
  assert pg_temp.ve('escritorio:dir-f') = 'o1,o2,o3,o4,o5,o6', 'diretoria vê tudo';
  -- substituto do gerente da Qualidade, ausente hoje
  insert into public.docs values ('compras-ausencias', 'a1', jsonb_build_object('gestorId', 'gerente-q', 'substitutoId', 'sub-q', 'de', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'), 'ate', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')));
  insert into public.docs values ('compras-ordens', 'o7', '{"status":"recebido","setor":"Qualidade","pedido":{"id":"gerente-q"}}');
  insert into public.docs values ('compras-ordens', 'o8', '{"status":"recebido","setor":"Produção","pedido":{"id":"analista-p"}}');
  assert pg_temp.ve('escritorio:sub-q') = 'o2,o7', 'substituto: o próprio e o setor do gestor (sem a conferência de outros setores): ' || pg_temp.ve('escritorio:sub-q');
  raise notice 'compras-setor-sql: tudo certo';
end $t$;
