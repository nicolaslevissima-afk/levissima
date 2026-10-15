-- LEVÍSSIMA · 0006: ordens de produção, estoque de matéria-prima e garrafões 10L/20L.
--
-- Coleções novas na tabela "docs":
--   producao-ordens        ordens de produção (itens, matéria-prima prevista, consumo ao concluir)
--   mp-insumos             cadastro dos insumos (área "producao" ou "garrafoes")
--   mp-fichas              ficha técnica de cada produto (id = id do produto) e de cada garrafão (id = garrafao-<item>)
--   mp-movs                recebimentos, contagens e perdas de matéria-prima
--   garrafoes-fechamentos  fechamento do dia dos garrafões 10L/20L (id = data), com o consumo dos insumos
--   mp-config              configurações (doc "garrafoes": a lista dos garrafões)
--
-- Duas regras RESTRITIVAS (valem junto com as que já existem; nenhuma regra antiga muda):
--   1. essas coleções são só do escritório: senha mestre e senha da equipe (motorista e representante não leem);
--   2. o cadastro (insumos, fichas técnicas e configuração) só a senha mestre grava.

create or replace function public.colecao_producao(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('producao-ordens', 'mp-insumos', 'mp-fichas', 'mp-movs', 'garrafoes-fechamentos', 'mp-config'); $$;
revoke execute on function public.colecao_producao(text) from public, anon;
grant execute on function public.colecao_producao(text) to authenticated;

create or replace function public.colecao_cadastro_producao(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('mp-insumos', 'mp-fichas', 'mp-config'); $$;
revoke execute on function public.colecao_cadastro_producao(text) from public, anon;
grant execute on function public.colecao_cadastro_producao(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'producao_escritorio') then
    create policy "producao_escritorio" on public.docs as restrictive for all to authenticated
      using (not public.colecao_producao(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_producao(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'producao_cadastro_grava') then
    create policy "producao_cadastro_grava" on public.docs as restrictive for insert to authenticated
      with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'producao_cadastro_altera') then
    create policy "producao_cadastro_altera" on public.docs as restrictive for update to authenticated
      using (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre')
      with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'producao_cadastro_apaga') then
    create policy "producao_cadastro_apaga" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;
