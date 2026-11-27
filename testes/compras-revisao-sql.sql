-- LEVÍSSIMA · teste da 0065: quem autoriza altera o pedido com "só inclui" (com motivo) e as novidades vistas nas preferências.
-- Banco local mínimo (o mesmo começo de compras-setor-sql.sql). Rodar: createdb t && psql -d t -f testes/compras-revisao-sql.sql
\set ON_ERROR_STOP 1
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

create function public.so_inclui() returns boolean language sql stable as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'so_inclui')::boolean, false) $$;
create function public.chat_pode_0019() returns boolean language sql stable as $$ select public.papel_atual() in ('mestre', 'equipe') and public.ref_atual() <> '' $$;
create table public.preferencias (dono text primary key, dados jsonb not null default '{}'::jsonb check (jsonb_typeof(dados) = 'object' and length(dados::text) <= 20000), atualizado_em timestamptz not null default now());
\i supabase/migrations/0059_compras_dono_cancela_edita.sql
create trigger docs_oc_so_inclui_0058 before update on public.docs for each row execute function public.oc_so_inclui_0058();
create function pg_temp.como(p_ref text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('app_metadata', json_build_object('papel', 'equipe', 'ref', p_ref, 'so_inclui', true))::text, true) $f$;
create function pg_temp.altera(p_ref text, p_id text, p_patch jsonb) returns text language plpgsql as $f$
begin
  perform pg_temp.como(p_ref);
  update public.docs set data = data || p_patch where colecao = 'compras-ordens' and id = p_id;
  return 'ok';
exception when others then return 'recusado: ' || sqlerrm;
end $f$;
-- antes da 0065: o gerente da Qualidade (só inclui) não altera o pedido o2 (Qualidade) que espera a autorização
do $t$ begin
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"itens":[{"q":2}],"edicao":{"motivo":"duas unidades"}}') like 'recusado%', 'antes da 0065 recusava';
end $t$;
\i supabase/migrations/0065_compras_quem_autoriza_altera_novidades.sql
\i supabase/migrations/0065_compras_quem_autoriza_altera_novidades.sql
do $t$ begin
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"itens":[{"q":2}],"edicao":{"motivo":"duas unidades"}}') = 'ok', 'gerente da Qualidade altera o pedido da Qualidade com motivo';
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"itens":[{"q":3}],"edicao":{"motivo":""}}') like 'recusado: Escreva o motivo%', 'sem motivo: recusado';
  assert pg_temp.altera('escritorio:gerente-q', 'o6', '{"itens":[{"q":2}],"edicao":{"motivo":"duas unidades"}}') like 'recusado%', 'pedido de outro setor (Manutenção): recusado';
  assert pg_temp.altera('escritorio:super-m', 'o6', '{"itens":[{"q":2}],"edicao":{"motivo":"duas unidades"}}') = 'ok', 'supervisor da Manutenção altera o pedido da Manutenção';
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"pedido":{"id":"gerente-q"},"edicao":{"motivo":"trocar quem pediu"}}') like 'recusado%', 'não muda quem pediu';
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"status":"cancelada","cancelamento":{"motivo":"não precisa"}}') like 'recusado%', 'quem autoriza não cancela por aqui';
  assert pg_temp.altera('escritorio:analista-p', 'o2', '{"itens":[{"q":9}],"edicao":{"motivo":"não sou gestor"}}') like 'recusado%', 'quem não autoriza continua sem alterar';
  assert pg_temp.altera('escritorio:compras-a', 'o1', '{"itens":[{"q":2}],"edicao":{"motivo":"compras ajusta"}}') = 'ok', 'Compras altera';
  assert pg_temp.altera('escritorio:gerente-q', 'o5', '{"itens":[{"q":2}],"edicao":{"motivo":"já em cotação"}}') like 'recusado%', 'depois da autorização (cotação): recusado';
  assert pg_temp.altera('escritorio:gerente-q', 'o2', '{"status":"cotacao","coord":{"id":"gerente-q","nome":"Gerente Q"}}') = 'ok', 'assinar a autorização continua valendo (0058)';
end $t$;
-- novidades vistas nas preferências
do $t$
declare v jsonb;
begin
  perform pg_temp.como('escritorio:gerente-q');
  perform public.preferencia_gravar('abas', '["cargas","compras"]');
  perform public.preferencia_gravar('novidades', '{"abc123":"2026-11-27T03:00:00.000Z","x9":"2026-11-27T03:01:00.000Z"}');
  select dados into v from public.preferencias where dono = 'escritorio:gerente-q';
  assert v -> 'abas' = '["cargas","compras"]'::jsonb and v -> 'novidades' ->> 'abc123' = '2026-11-27T03:00:00.000Z', 'grava as novidades sem apagar a ordem das abas: ' || v::text;
  begin perform public.preferencia_gravar('novidades', '{"COM ESPAÇO":"x"}'); assert false, 'aceitou código inválido'; exception when sqlstate '22023' then null; end;
  begin perform public.preferencia_gravar('novidades', '["a"]'); assert false, 'aceitou lista'; exception when sqlstate '22023' then null; end;
  begin perform public.preferencia_gravar('outra', '{}'); assert false, 'aceitou chave desconhecida'; exception when sqlstate '22023' then null; end;
end $t$;
select 'TUDO OK' as resultado;

