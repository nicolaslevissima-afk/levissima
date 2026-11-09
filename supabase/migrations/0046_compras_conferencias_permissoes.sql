-- LEVÍSSIMA · 0046: pedido de compra — duas conferências novas e "o que cada cargo faz" (pedido de 09/11/2026).
--
-- Fluxo: pedido → autorização → cotação → QUEM PEDIU CONFERE a cotação (status "revisao"; se não estiver de acordo,
-- volta para a cotação) → diretoria → comprado → recebido → CONFERÊNCIA do que chegou (status "recebido"; libera
-- para entregar = "conferido", ou devolve ao fornecedor = volta para "comprado") → entregue.
-- As assinaturas novas ("revisao" e "conferencia") também fazem quem assinou continuar vendo a ordem (como 0026).
--
-- Quem assina cada etapa é escolhido por cargo em Cadastros › Compras (coleção "compras-config", documento
-- "permissoes": { etapas: { coord: [...], cotacao: [...], ... } }), com os cargos da equipe, "sem-cargo" e as marcas
-- "marca:coordenador" (Autoriza compras), "marca:compras" e "marca:aprovaCompra". Sem nada salvo vale o padrão
-- (o mesmo de antes; ver oc_pode_etapa_0046). Quem faz a etapa em que a ordem está passa a vê-la. Só a senha mestre
-- (sem "só inclui") muda a configuração; o escritório lê.

create or replace function public.oc_funcoes_0046(m jsonb)
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $$
  select array_remove(array[
    case when coalesce(m ->> 'cargo', '') in ('diretor', 'gerente', 'coordenador', 'supervisor', 'executiva', 'analista', 'assistente', 'lider', 'operador', 'outro') then m ->> 'cargo'
         when m ->> 'cargo' = 'executiva_comercial' then 'executiva'
         else 'sem-cargo' end,
    case when m -> 'coordenador' = 'true'::jsonb then 'marca:coordenador' end,
    case when m -> 'compras' = 'true'::jsonb then 'marca:compras' end,
    case when m -> 'aprovaCompra' = 'true'::jsonb then 'marca:aprovaCompra' end
  ], null)
$$;
-- só usada dentro de oc_visivel_0025 (que roda como dona): ninguém chama direto
revoke execute on function public.oc_funcoes_0046(jsonb) from public, anon, authenticated;

create or replace function public.oc_pode_etapa_0046(m jsonb, p_etapa text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare cfg jsonb; lista text[];
begin
  if m is null then return false; end if;
  select data -> 'etapas' -> p_etapa into cfg from public.docs where colecao = 'compras-config' and id = 'permissoes';
  if jsonb_typeof(cfg) = 'array' then
    select coalesce(array_agg(x), '{}') into lista from jsonb_array_elements_text(cfg) as x;
  else
    lista := case p_etapa
      when 'coord' then array['gerente', 'coordenador', 'supervisor', 'marca:coordenador']
      when 'cotacao' then array['marca:compras']
      when 'aprovacao' then array['diretor', 'marca:aprovaCompra']
      when 'compra' then array['diretor', 'marca:compras', 'marca:aprovaCompra']
      when 'recebimento' then array['diretor', 'gerente', 'coordenador', 'supervisor', 'executiva', 'analista', 'assistente', 'lider', 'operador', 'outro', 'sem-cargo', 'marca:coordenador', 'marca:compras', 'marca:aprovaCompra']
      when 'conferencia' then array['diretor', 'gerente', 'coordenador', 'supervisor', 'marca:compras', 'marca:aprovaCompra']
      else array[]::text[] end;
  end if;
  return public.oc_funcoes_0046(m) && lista;
end $$;
revoke execute on function public.oc_pode_etapa_0046(jsonb, text) from public, anon, authenticated;

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
  etapa text;
begin
  if p = 'mestre' then return true; end if;
  if p <> 'equipe' then return false; end if;
  if st = 'comprado' then return true; end if;
  if r like 'escritorio:%' then eid := substr(r, 12); end if;
  foreach k in array array['pedido', 'coord', 'cotacao', 'revisao', 'aprovacao', 'compra', 'recebimento', 'conferencia', 'fechamento', 'edicao', 'cancelamento'] loop
    if jsonb_typeof(d -> k) = 'object' then
      if r <> '' and coalesce(d -> k ->> 'ref', '') = r then return true; end if;
      if eid <> '' and coalesce(d -> k ->> 'id', '') = eid then return true; end if;
    end if;
  end loop;
  if eid = '' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = eid;
  if m is null then return false; end if;
  if m -> 'compras' = 'true'::jsonb or m -> 'aprovaCompra' = 'true'::jsonb or m ->> 'cargo' = 'diretor' then return true; end if;
  -- quem autoriza: as do(s) setor(es) que autoriza (em branco: as da área dele e as que esperam autorização)
  if public.oc_pode_etapa_0046(m, 'coord') then
    select coalesce(array_agg(x), '{}') into setores
      from (select public.sem_acento_0009(s) as x from regexp_split_to_table(coalesce(m ->> 'setores', ''), '[,;\n]+') as s) t
     where x <> '';
    if cardinality(setores) > 0 then
      if setor = any(setores) then return true; end if;
    elsif st = 'pedido' or (setor <> '' and setor = public.sem_acento_0009(m ->> 'area')) then
      return true;
    end if;
  end if;
  -- quem faz a etapa em que a ordem está (Cadastros › Compras)
  etapa := case st when 'cotacao' then 'cotacao' when 'justificativa' then 'justificativa' when 'revisao' then 'revisao'
    when 'aprovacao' then 'aprovacao' when 'compra' then 'compra' when 'recebido' then 'conferencia' when 'conferido' then 'entrega' else '' end;
  if etapa <> '' and public.oc_pode_etapa_0046(m, etapa) then return true; end if;
  return false;
end $$;
revoke execute on function public.oc_visivel_0025(jsonb) from public, anon;
grant execute on function public.oc_visivel_0025(jsonb) to authenticated;

-- configuração (Cadastros › Compras): o escritório lê; só a senha mestre (sem "só inclui") grava ou apaga
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_config_le_0046') then
    create policy "compras_config_le_0046" on public.docs as restrictive for all to authenticated
      using (colecao <> 'compras-config' or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (colecao <> 'compras-config' or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_config_grava_0046') then
    create policy "compras_config_grava_0046" on public.docs as restrictive for insert to authenticated
      with check (colecao <> 'compras-config' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_config_altera_0046') then
    create policy "compras_config_altera_0046" on public.docs as restrictive for update to authenticated
      using (colecao <> 'compras-config' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())))
      with check (colecao <> 'compras-config' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_config_apaga_0046') then
    create policy "compras_config_apaga_0046" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'compras-config' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
end $$;
