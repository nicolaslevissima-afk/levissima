-- LEVÍSSIMA · 0063: Compras — cada um vê só o que é seu (pedido de 23/11/2026).
-- * Supervisor, coordenador e gerente (quem autoriza, Cadastros › Compras) veem os pedidos do setor deles: os setores
--   marcados em "Setores que autoriza" ou, em branco, os da área da pessoa. Antes, com os setores em branco, viam
--   também os pedidos de todos os setores esperando autorização.
-- * Os demais veem só os pedidos que fizeram. A compra já feita ("Para receber") não aparece mais para todos: quem
--   recebe é quem pediu, o gestor do setor ou Compras.
-- * Continuam vendo tudo: a senha mestre, Compras (marca "compras"), quem aprova (marca "aprovaCompra") e a
--   diretoria (cargo diretor). Setor sem gestor no cadastro (ex.: Expedição): fica com a diretoria e Compras.
-- * Quem faz uma etapa que não é de setor (cotação, justificativa, revisão, aprovação, compra) continua vendo as
--   ordens nessa etapa. A conferência e a entrega seguem o setor.
-- * Substituto de gestor ausente: os pedidos do gestor e os do setor dele (como antes, sem as conferências de outros
--   setores). O gestor vê o que o substituto assinou no lugar dele.

-- setor de quem autoriza: com setores marcados, esses; em branco, a área da pessoa
create or replace function public.oc_setor_visivel_0047(m jsonb, st text, setor text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare setores text[];
begin
  if m is null or not public.oc_pode_etapa_0046(m, 'coord') then return false; end if;
  select coalesce(array_agg(x), '{}') into setores
    from (select public.sem_acento_0009(s) as x from regexp_split_to_table(coalesce(m ->> 'setores', ''), '[,;\n]+') as s) t
   where x <> '';
  if cardinality(setores) > 0 then return setor = any(setores); end if;
  return setor <> '' and setor = public.sem_acento_0009(m ->> 'area');
end $$;
revoke execute on function public.oc_setor_visivel_0047(jsonb, text, text) from public, anon, authenticated;

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
  etapa text;
  a jsonb;
  g jsonb;
  gid text;
  hoje text;
begin
  if p = 'mestre' then return true; end if;
  if p <> 'equipe' then return false; end if;
  if r like 'escritorio:%' then eid := substr(r, 12); end if;
  -- o pedido que a pessoa fez
  if jsonb_typeof(d -> 'pedido') = 'object'
     and ((r <> '' and coalesce(d -> 'pedido' ->> 'ref', '') = r) or (eid <> '' and coalesce(d -> 'pedido' ->> 'id', '') = eid)) then
    return true;
  end if;
  if eid = '' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = eid;
  if m is null then return false; end if;
  -- Compras, quem aprova e a diretoria: tudo
  if m -> 'compras' = 'true'::jsonb or m -> 'aprovaCompra' = 'true'::jsonb or m ->> 'cargo' = 'diretor' then return true; end if;
  -- supervisor, coordenador e gerente: o setor deles e o que assinaram
  if public.oc_pode_etapa_0046(m, 'coord') then
    if public.oc_setor_visivel_0047(m, st, setor) then return true; end if;
    foreach k in array array['coord', 'cotacao', 'revisao', 'aprovacao', 'compra', 'recebimento', 'conferencia', 'fechamento', 'edicao', 'cancelamento'] loop
      if jsonb_typeof(d -> k) = 'object' then
        if r <> '' and coalesce(d -> k ->> 'ref', '') = r then return true; end if;
        if coalesce(d -> k ->> 'id', '') = eid then return true; end if;
      end if;
    end loop;
    -- o que o substituto assinou no lugar do gestor: o gestor vê (histórico da ausência)
    if jsonb_typeof(d -> 'substituicoes') = 'array'
       and exists (select 1 from jsonb_array_elements(d -> 'substituicoes') x where x ->> 'gestorId' = eid) then return true; end if;
  end if;
  -- quem faz uma etapa que não é de setor (Cadastros › Compras): as ordens que estão nessa etapa
  etapa := case st when 'cotacao' then 'cotacao' when 'justificativa' then 'justificativa' when 'revisao' then 'revisao'
    when 'aprovacao' then 'aprovacao' when 'compra' then 'compra' else '' end;
  if etapa <> '' and public.oc_pode_etapa_0046(m, etapa) then return true; end if;
  -- substituto de um gestor ausente hoje: os pedidos do gestor e os do setor dele
  hoje := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
  for a in
    select data from public.docs
     where colecao = 'compras-ausencias' and data ->> 'substitutoId' = eid
       and coalesce(data ->> 'encerradaEm', '') = '' and data ->> 'de' <= hoje and data ->> 'ate' >= hoje
  loop
    gid := coalesce(a ->> 'gestorId', '');
    if gid = '' or gid = eid then continue; end if;
    if coalesce(d -> 'pedido' ->> 'id', '') = gid then return true; end if;
    select data into g from public.docs where colecao = 'equipe' and id = gid;
    if g is null then continue; end if;
    if public.oc_setor_visivel_0047(g, st, setor) then return true; end if;
  end loop;
  return false;
end $$;
revoke execute on function public.oc_visivel_0025(jsonb) from public, anon;
grant execute on function public.oc_visivel_0025(jsonb) to authenticated;
