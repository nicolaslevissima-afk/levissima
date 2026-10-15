-- LEVÍSSIMA · 0005: Força de vendas (portal dos representantes).
--
-- Papel novo "representante": cada representante entra com a própria senha (ref "representante:<id>").
-- O representante:
--   lê só os produtos, os nomes dos destinos de frete (config/fretes-destinos) e as cargas que ele mesmo lançou;
--   grava só cargas dele (origem "representante", status "aberta") e só enquanto elas ainda não têm o ok do
--   financeiro nem o ok da logística — depois disso a carga fica com o escritório.
-- O cadastro dos representantes e os documentos/contratos deles são só da senha mestre
-- (coleções "representantes" e "representante-docs"; os arquivos ficam no bucket privado "motoristas-docs",
-- na pasta representantes/).
--
-- A regra de papéis da tabela acesso_senhas é refeita com "representante" na lista (nenhuma senha é apagada).

alter table public.acesso_senhas drop constraint if exists acesso_senhas_papel_check;
alter table public.acesso_senhas add constraint acesso_senhas_papel_check
  check (papel in ('mestre', 'equipe', 'motorista', 'setor', 'representante'));

create or replace function public.ref_atual()
returns text
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'ref', ''); $$;
revoke execute on function public.ref_atual() from public, anon;
grant execute on function public.ref_atual() to authenticated;

create or replace function public.colecao_so_mestre(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('fretes', 'fretes-tabela', 'motorista-docs', 'representantes', 'representante-docs'); $$;

-- Carga do próprio representante, ainda sem nenhum ok: é a única coisa que ele pode gravar ou apagar.
create or replace function public.carga_do_representante(p_colecao text, p_dados jsonb)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select p_colecao = 'cargas'
     and public.ref_atual() like 'representante:%'
     and coalesce(p_dados ->> 'representanteRef', '') = public.ref_atual()
     and coalesce(p_dados ->> 'origem', '') = 'representante'
     and coalesce(p_dados ->> 'status', 'aberta') = 'aberta'
     and coalesce(p_dados ->> 'financeiroOk', 'false') <> 'true'
     and coalesce(p_dados ->> 'logisticaOk', 'false') <> 'true';
$$;
revoke execute on function public.carga_do_representante(text, jsonb) from public, anon;
grant execute on function public.carga_do_representante(text, jsonb) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'rep_le') then
    create policy "rep_le" on public.docs for select to authenticated
      using ((select public.papel_atual()) = 'representante'
             and (colecao = 'produtos'
                  or (colecao = 'config' and id = 'fretes-destinos')
                  or (colecao = 'cargas' and data ->> 'representanteRef' = (select public.ref_atual()))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'rep_grava') then
    create policy "rep_grava" on public.docs for insert to authenticated
      with check ((select public.papel_atual()) = 'representante' and public.carga_do_representante(colecao, data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'rep_altera') then
    create policy "rep_altera" on public.docs for update to authenticated
      using ((select public.papel_atual()) = 'representante' and public.carga_do_representante(colecao, data))
      with check ((select public.papel_atual()) = 'representante' and public.carga_do_representante(colecao, data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'rep_apaga') then
    create policy "rep_apaga" on public.docs for delete to authenticated
      using ((select public.papel_atual()) = 'representante' and public.carga_do_representante(colecao, data));
  end if;
end $$;
