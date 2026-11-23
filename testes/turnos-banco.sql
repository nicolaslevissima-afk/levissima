-- LEVÍSSIMA · teste da 0062 (turnos do RH): simulação mínima do Supabase (docs, papéis e regras da produção).
-- Rodar: createdb t && psql -d t -f testes/turnos-banco.sql && psql -d t -f supabase/migrations/0052_pcp_programacao.sql
--        && psql -d t -f testes/turnos-linhas.sql && psql -d t -f supabase/migrations/0062_turnos_do_rh.sql && psql -d t -f testes/turnos-sql.sql
do $r$ begin if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end $r$;
create schema if not exists auth;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;
create table public.docs (colecao text not null, id text not null, data jsonb not null default '{}'::jsonb, atualizado_em timestamptz not null default now(), primary key (colecao, id));
alter table public.docs enable row level security;
grant select, insert, update, delete on public.docs to authenticated;
create function public.papel_atual() returns text language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') $$;
create function public.ref_atual() returns text language sql stable as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'ref', '') $$;
create function public.so_inclui() returns boolean language sql stable as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'so_inclui')::boolean, false) $$;
create function public.so_ver() returns boolean language sql stable as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'so_ver')::boolean, false) $$;
create function public.colecao_cadastro_producao(p_colecao text) returns boolean language sql immutable as $$ select p_colecao in ('mp-insumos', 'mp-fichas', 'mp-config') $$;
create function public.grava_aba_marcada_0042(p_aba text) returns boolean language sql stable as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() = 'equipe'
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?& array['abas', 'aba:' || p_aba], false)
          and not coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?| array['ver:' || p_aba, 'inclui:' || p_aba], false)
          and not public.so_ver() and not public.so_inclui()); $$;
create policy le on public.docs for select to authenticated using ((select public.papel_atual()) in ('mestre', 'equipe'));
create policy grava on public.docs for insert to authenticated with check ((select public.papel_atual()) in ('mestre', 'equipe'));
create policy altera on public.docs for update to authenticated using ((select public.papel_atual()) in ('mestre', 'equipe')) with check ((select public.papel_atual()) in ('mestre', 'equipe'));
create policy producao_cadastro_grava on public.docs as restrictive for insert to authenticated with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre');
create policy producao_cadastro_altera on public.docs as restrictive for update to authenticated using (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre') with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre');
