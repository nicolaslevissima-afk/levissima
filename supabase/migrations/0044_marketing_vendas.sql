-- LEVÍSSIMA · 0044: material de marketing e painel de vendas (pedido de 05/11/2026).
--
-- 1. Material de marketing: coleções 'mkt-materiais' (cadastro: estoque mínimo e tempo de produção) e 'mkt-movs'
--    (entradas, entregas para clientes, funcionários e vendedores, contagens). Só o escritório (senha mestre e equipe)
--    lê e grava; só a senha mestre apaga. O app nunca apaga: lançamento errado é cancelado com o motivo e continua no
--    histórico. Quem vê a aba: senha mestre, diretoria, senha da equipe e quem tem "Vê a aba Material de marketing"
--    em Cadastros › Equipe (o app decide; o banco segura o escritório).
-- 2. Painel de vendas: 'vendas-config' (preços de referência por produto, opcionais) só para a senha mestre, a
--    diretoria e quem tem "Vê o painel de Vendas" em Cadastros › Equipe; só a senha mestre apaga. O painel lê as
--    cargas, que o escritório já lê.

create or replace function public.colecao_marketing_0044(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp
as $$ select p_colecao in ('mkt-materiais', 'mkt-movs'); $$;
revoke execute on function public.colecao_marketing_0044(text) from public, anon;
grant execute on function public.colecao_marketing_0044(text) to authenticated;

-- quem vê o painel de vendas: senha mestre e diretoria (papel 'mestre') ou a pessoa do escritório marcada
create or replace function public.vendas_pode_0044()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); m jsonb;
begin
  if coalesce(public.papel_atual(), '') = 'mestre' then return true; end if;
  if coalesce(public.papel_atual(), '') <> 'equipe' or r not like 'escritorio:%' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  return coalesce(m -> 'veVendas' = 'true'::jsonb, false);
end $$;
revoke execute on function public.vendas_pode_0044() from public, anon;
grant execute on function public.vendas_pode_0044() to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'marketing_0044') then
    create policy "marketing_0044" on public.docs as restrictive for all to authenticated
      using (not public.colecao_marketing_0044(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_marketing_0044(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'marketing_apaga_0044') then
    create policy "marketing_apaga_0044" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_marketing_0044(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'vendas_0044') then
    create policy "vendas_0044" on public.docs as restrictive for all to authenticated
      using (colecao <> 'vendas-config' or (select public.vendas_pode_0044()))
      with check (colecao <> 'vendas-config' or (select public.vendas_pode_0044()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'vendas_apaga_0044') then
    create policy "vendas_apaga_0044" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'vendas-config' or (select public.papel_atual()) = 'mestre');
  end if;
end $$;
