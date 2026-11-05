-- LEVÍSSIMA · 0043: pedido de compra — alterar só antes da cotação e cancelar com motivo (pedido de 04/11/2026).
--
-- 1. Quem alterou o pedido (campo "edicao") ou cancelou a ordem (campo "cancelamento") continua vendo a ordem:
--    a gravação devolve a ordem, então ela precisa estar visível para quem grava (mesma regra das assinaturas, 0026).
-- 2. Gatilho: depois que a ordem sai de "pedido" (foi para a cotação ou adiante), os itens, o setor, a urgência e a
--    justificativa do pedido não mudam mais, para ninguém do escritório. Só a senha mestre passa (restaurar uma
--    versão pela lixeira, por exemplo). A gravação inteira com os mesmos itens (assinar uma etapa) continua normal.

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
  foreach k in array array['pedido', 'coord', 'cotacao', 'aprovacao', 'compra', 'recebimento', 'fechamento', 'edicao', 'cancelamento'] loop
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

-- gatilho: depois da cotação, o pedido (itens, setor, urgência, justificativa) fica travado
create or replace function public.oc_trava_0043()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.colecao <> 'compras-ordens' or tg_op <> 'UPDATE' then return new; end if; -- a gravação inteira chega aqui como UPDATE (on conflict)
  if auth.jwt() is null then return new; end if; -- manutenção direta no banco
  if coalesce(public.papel_atual(), '') = 'mestre' and not public.so_inclui() then return new; end if;
  if coalesce(old.data ->> 'status', '') = 'pedido' then return new; end if;
  if (new.data -> 'itens') is distinct from (old.data -> 'itens')
     or (new.data -> 'setor') is distinct from (old.data -> 'setor')
     or (new.data -> 'urgencia') is distinct from (old.data -> 'urgencia')
     or (new.data -> 'obs') is distinct from (old.data -> 'obs') then
    raise exception 'oc_travada' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function public.oc_trava_0043() from public, anon, authenticated;

create or replace trigger docs_oc_trava_0043 before update on public.docs
  for each row execute function public.oc_trava_0043();
