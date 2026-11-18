-- LEVÍSSIMA · teste da 0056 (Garrafões): simulação mínima do Supabase num Postgres local.
-- Rodar: createdb t && psql -d t -f testes/garrafoes-banco.sql && psql -d t -f supabase/migrations/0056_garrafoes_estoque.sql && psql -d t -f testes/garrafoes-sql.sql
do $r$ begin if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end $r$;
create schema auth;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create table public.acesso_senhas (ref text primary key, papel text, nome text, hash text, modulos text[] not null default '{}');

create or replace function public.pode_modulo(p_modulo text)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'mestre'
      or (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') in ('equipe', 'setor')
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?| array[p_modulo, p_modulo || ':gerir'], false));
$$;
grant execute on function public.pode_modulo(text) to authenticated;

create table public.modulo_docs (
  modulo text not null check (modulo in ('manutencao', 'empilhadeiras', 'uniformes', 'garrafoes')),
  caminho text not null, id text not null, dados jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(), primary key (modulo, caminho, id));
alter table public.modulo_docs enable row level security;
grant select, insert, update, delete on public.modulo_docs to authenticated;
create policy "modulo_le" on public.modulo_docs for select to authenticated using (public.pode_modulo(modulo));
create policy "modulo_grava" on public.modulo_docs for insert to authenticated with check (public.pode_modulo(modulo));
create policy "modulo_altera" on public.modulo_docs for update to authenticated using (public.pode_modulo(modulo)) with check (public.pode_modulo(modulo));
create policy "modulo_apaga" on public.modulo_docs for delete to authenticated using (public.pode_modulo(modulo));

insert into public.acesso_senhas (ref, papel, nome, modulos) values
  ('escritorio:gestora', 'equipe', 'Gestora', '{garrafoes:gerir,abas}'),
  ('escritorio:conta', 'equipe', 'Contadora', '{garrafoes,abas}'),
  ('escritorio:entrega', 'equipe', 'Entregador', '{garrafoes,abas}'),
  ('escritorio:outro', 'equipe', 'Sem módulo', '{manutencao,abas}'),
  ('setor:expedicao', 'setor', 'Expedição', '{garrafoes}');
insert into public.modulo_docs (modulo, caminho, id, dados) values
  ('garrafoes', 'movimentos', 'sucata-20L-20260928', '{"tipo":"sucata_ini","qtd":30,"produto":"20L"}'),
  ('garrafoes', 'config', 'geral', '{"validadeAnos":3}');
