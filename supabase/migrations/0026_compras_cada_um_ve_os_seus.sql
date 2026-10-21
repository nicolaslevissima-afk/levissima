-- LEVÍSSIMA · 0026: pedido de compras — cada pessoa vê só os próprios pedidos (pedido de 20/10/2026).
--
-- Coleção compras-ordens (tabela docs). Quem lê cada ordem:
--   1. senha mestre e acessos da diretoria (papel 'mestre' no login): todas;
--   2. pessoa do escritório (acesso pessoal "escritorio:<id da equipe>"):
--      - compras (Assistente de compras) e diretoria (cargo diretor ou "Aprova compras"): todas;
--      - coordenador, supervisor ou gerente (ou "Autoriza compras"): as do(s) setor(es) que autoriza
--        (campo "Setores que autoriza"; em branco: as da área dele e as que esperam autorização de qualquer setor);
--      - todos: as que pediu ou em que assinou alguma etapa (pelo id da equipe ou pelo acesso usado);
--   3. qualquer pessoa do escritório: as já compradas que aguardam chegar (status "comprado"), para dar o recebido.
-- Gravar continua igual (escritório grava, só a senha mestre apaga); como a gravação devolve a ordem, ela também
-- precisa estar visível para quem grava: por isso quem assina uma etapa passa a ver aquela ordem.

create or replace function public.oc_visivel_0025(d jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  p text := coalesce(public.papel_atual(), '');
  r text := coalesce(public.ref_atual(), '');
  eid text := '';
  m jsonb;
  k text;
  st text := coalesce(d ->> 'status', '');
  setor text := public.sem_acento_0009(d ->> 'setor');
  setores text[];
begin
  if p = 'mestre' then return true; end if;
  if p <> 'equipe' then return false; end if;
  if st = 'comprado' then return true; end if;
  if r like 'escritorio:%' then eid := substr(r, 12); end if;
  foreach k in array array['pedido', 'coord', 'cotacao', 'aprovacao', 'compra', 'recebimento', 'fechamento'] loop
    if jsonb_typeof(d -> k) = 'object' then
      if r <> '' and coalesce(d -> k ->> 'ref', '') = r then return true; end if;
      if eid <> '' and coalesce(d -> k ->> 'id', '') = eid then return true; end if;
    end if;
  end loop;
  if eid = '' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = eid;
  if m is null then return false; end if;
  if m -> 'compras' = 'true'::jsonb or m -> 'aprovaCompra' = 'true'::jsonb or m ->> 'cargo' = 'diretor' then return true; end if;
  if m -> 'coordenador' = 'true'::jsonb or coalesce(m ->> 'cargo', '') in ('coordenador', 'supervisor', 'gerente') then
    select coalesce(array_agg(x), '{}') into setores
      from (select public.sem_acento_0009(s) as x from regexp_split_to_table(coalesce(m ->> 'setores', ''), '[,;\n]+') as s) t
     where x <> '';
    if cardinality(setores) > 0 then return setor = any(setores); end if;
    return st = 'pedido' or (setor <> '' and setor = public.sem_acento_0009(m ->> 'area'));
  end if;
  return false;
end $$;
revoke execute on function public.oc_visivel_0025(jsonb) from public, anon;
grant execute on function public.oc_visivel_0025(jsonb) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_ve_0025') then
    create policy "compras_ve_0025" on public.docs as restrictive for select to authenticated
      using (colecao <> 'compras-ordens' or public.oc_visivel_0025(data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_altera_0025') then
    create policy "compras_altera_0025" on public.docs as restrictive for update to authenticated
      using (colecao <> 'compras-ordens' or public.oc_visivel_0025(data));
  end if;
end $$;
