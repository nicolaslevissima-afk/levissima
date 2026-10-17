-- LEVÍSSIMA · 0007: reserva das salas de reunião, aba Qualidade e logos das marcas.
--
-- Coleções novas na tabela "docs":
--   salas-reservas          reservas das salas (Levíssima Protein e PH+8); cancelar não apaga (fica cancelada)
--   qualidade-recebimentos  inspeção dos insumos no recebimento
--   qualidade-checklists    checklist de linha (pré-operacional, verificação de processo, garrafões)
--   qualidade-analises      análises microbiológicas, físico-químicas e outras
--   qualidade-ncs           não conformidades (contenção, causa, ação corretiva, eficácia)
--   qualidade-config        plano de qualidade (doc "plano")
--   marcas                  logo de cada marca (id = marca)
--
-- Regras RESTRITIVAS (somam com as que já existem; nenhuma regra antiga muda):
--   1. salas e qualidade são só do escritório: senha mestre e senha da equipe (motorista e representante não leem);
--   2. o plano de qualidade e os logos das marcas só a senha mestre grava (todos os que já leem continuam lendo).

create or replace function public.colecao_escritorio_0007(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('salas-reservas', 'qualidade-recebimentos', 'qualidade-checklists', 'qualidade-analises', 'qualidade-ncs', 'qualidade-config'); $$;
revoke execute on function public.colecao_escritorio_0007(text) from public, anon;
grant execute on function public.colecao_escritorio_0007(text) to authenticated;

create or replace function public.colecao_grava_mestre_0007(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('qualidade-config', 'marcas'); $$;
revoke execute on function public.colecao_grava_mestre_0007(text) from public, anon;
grant execute on function public.colecao_grava_mestre_0007(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'escritorio_0007') then
    create policy "escritorio_0007" on public.docs as restrictive for all to authenticated
      using (not public.colecao_escritorio_0007(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_escritorio_0007(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_grava_0007') then
    create policy "mestre_grava_0007" on public.docs as restrictive for insert to authenticated
      with check (not public.colecao_grava_mestre_0007(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_altera_0007') then
    create policy "mestre_altera_0007" on public.docs as restrictive for update to authenticated
      using (not public.colecao_grava_mestre_0007(colecao) or (select public.papel_atual()) = 'mestre')
      with check (not public.colecao_grava_mestre_0007(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_apaga_0007') then
    create policy "mestre_apaga_0007" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_grava_mestre_0007(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;
