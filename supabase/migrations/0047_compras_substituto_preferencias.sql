-- LEVÍSSIMA · 0047: substituto do gestor nas compras e ordem das abas de cada perfil (pedidos de 09/11/2026).
--
-- 1. SUBSTITUTO. Coleção "compras-ausencias" (tabela docs): { gestorId, gestorNome, substitutoId, substitutoNome,
--    de, ate (AAAA-MM-DD), motivo, obs, encerradaEm?, cancelada?, vistoEm? }. No período (de..ate, sem "encerradaEm"),
--    as autorizações e as conferências de compras do gestor caem para o substituto: ele passa a ver o que o gestor
--    veria pelo setor que autoriza, pelas etapas "conferir a cotação", "conferir o que chegou" e "confirmar a entrega"
--    e os pedidos do próprio gestor. A aprovação da diretoria, a cotação e a compra NÃO passam para o substituto.
--    Quem registra: o próprio gestor (acesso pessoal, só a ausência dele) ou a senha mestre / diretoria (de qualquer
--    um). O escritório lê; só a senha mestre apaga.
--    O que o substituto assina no lugar do gestor fica em "substituicoes" na ordem de compra: o gestor continua vendo
--    essas ordens na volta (histórico).
-- 2. PREFERÊNCIAS de cada acesso (tabela "preferencias", como os post-its da 0019): só o dono lê; grava pela função
--    preferencia_gravar. Hoje guarda a ordem das abas do menu (chave "abas": lista de abas na sequência escolhida).

-- regra do setor de quem autoriza (saiu de oc_visivel_0025 para servir também ao substituto)
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
  -- em branco: as da área dele e as que esperam autorização
  return st = 'pedido' or (setor <> '' and setor = public.sem_acento_0009(m ->> 'area'));
end $$;
-- só usada dentro de oc_visivel_0025 (que roda como dona): ninguém chama direto
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
  if st = 'comprado' then return true; end if;
  if r like 'escritorio:%' then eid := substr(r, 12); end if;
  foreach k in array array['pedido', 'coord', 'cotacao', 'revisao', 'aprovacao', 'compra', 'recebimento', 'conferencia', 'fechamento', 'edicao', 'cancelamento'] loop
    if jsonb_typeof(d -> k) = 'object' then
      if r <> '' and coalesce(d -> k ->> 'ref', '') = r then return true; end if;
      if eid <> '' and coalesce(d -> k ->> 'id', '') = eid then return true; end if;
    end if;
  end loop;
  if eid = '' then return false; end if;
  -- o que o substituto assinou no lugar do gestor: o gestor vê (histórico da ausência)
  if jsonb_typeof(d -> 'substituicoes') = 'array'
     and exists (select 1 from jsonb_array_elements(d -> 'substituicoes') x where x ->> 'gestorId' = eid) then return true; end if;
  select data into m from public.docs where colecao = 'equipe' and id = eid;
  if m is null then return false; end if;
  if m -> 'compras' = 'true'::jsonb or m -> 'aprovaCompra' = 'true'::jsonb or m ->> 'cargo' = 'diretor' then return true; end if;
  -- quem autoriza: as do(s) setor(es) que autoriza
  if public.oc_setor_visivel_0047(m, st, setor) then return true; end if;
  -- quem faz a etapa em que a ordem está (Cadastros › Compras)
  etapa := case st when 'cotacao' then 'cotacao' when 'justificativa' then 'justificativa' when 'revisao' then 'revisao'
    when 'aprovacao' then 'aprovacao' when 'compra' then 'compra' when 'recebido' then 'conferencia' when 'conferido' then 'entrega' else '' end;
  if etapa <> '' and public.oc_pode_etapa_0046(m, etapa) then return true; end if;
  -- substituto de um gestor ausente hoje: o que o gestor veria pelo setor e pelas conferências, e os pedidos do gestor
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
    if etapa in ('revisao', 'conferencia', 'entrega') and public.oc_pode_etapa_0046(g, etapa) then return true; end if;
  end loop;
  return false;
end $$;
revoke execute on function public.oc_visivel_0025(jsonb) from public, anon;
grant execute on function public.oc_visivel_0025(jsonb) to authenticated;

-- quem pode gravar uma ausência: o próprio gestor (acesso pessoal) ou a senha mestre / diretoria; datas e pessoas válidas
create or replace function public.ausencia_pode_0047(d jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  p text := coalesce(public.papel_atual(), '');
  r text := coalesce(public.ref_atual(), '');
begin
  if coalesce(d ->> 'gestorId', '') = '' or coalesce(d ->> 'substitutoId', '') = '' or d ->> 'gestorId' = d ->> 'substitutoId' then return false; end if;
  if coalesce(d ->> 'de', '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(d ->> 'ate', '') !~ '^\d{4}-\d{2}-\d{2}$' or d ->> 'de' > d ->> 'ate' then return false; end if;
  if p = 'mestre' then return true; end if;
  return p = 'equipe' and r = 'escritorio:' || (d ->> 'gestorId');
end $$;
revoke execute on function public.ausencia_pode_0047(jsonb) from public, anon;
grant execute on function public.ausencia_pode_0047(jsonb) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_ausencias_le_0047') then
    create policy "compras_ausencias_le_0047" on public.docs as restrictive for select to authenticated
      using (colecao <> 'compras-ausencias' or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_ausencias_grava_0047') then
    create policy "compras_ausencias_grava_0047" on public.docs as restrictive for insert to authenticated
      with check (colecao <> 'compras-ausencias' or public.ausencia_pode_0047(data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_ausencias_altera_0047') then
    create policy "compras_ausencias_altera_0047" on public.docs as restrictive for update to authenticated
      using (colecao <> 'compras-ausencias' or public.ausencia_pode_0047(data))
      with check (colecao <> 'compras-ausencias' or public.ausencia_pode_0047(data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_ausencias_apaga_0047') then
    create policy "compras_ausencias_apaga_0047" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'compras-ausencias' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
end $$;

-- ---------- preferências de cada acesso (a ordem das abas) ----------
create table if not exists public.preferencias (
  dono text primary key,
  dados jsonb not null default '{}'::jsonb check (jsonb_typeof(dados) = 'object' and length(dados::text) <= 20000),
  atualizado_em timestamptz not null default now()
);
alter table public.preferencias enable row level security;
revoke all on public.preferencias from public, anon, authenticated;
grant select on public.preferencias to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'preferencias' and policyname = 'preferencias_dono_0047') then
    create policy preferencias_dono_0047 on public.preferencias for select to authenticated
      using ((select public.ref_atual()) <> '' and dono = (select public.ref_atual()));
  end if;
end $$;

-- grava uma preferência do próprio acesso (p_valor nulo apaga a chave)
create or replace function public.preferencia_gravar(p_chave text, p_valor jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.preferencias;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if p_chave is null or p_chave not in ('abas') then raise exception 'chave' using errcode = '22023'; end if;
  if p_valor is null or jsonb_typeof(p_valor) = 'null' then
    update public.preferencias set dados = dados - p_chave, atualizado_em = now() where dono = public.ref_atual() returning * into r;
    return coalesce(to_jsonb(r), '{}'::jsonb);
  end if;
  -- abas: lista de até 80 nomes curtos (ex.: "cargas", "mod:manutencao")
  if jsonb_typeof(p_valor) <> 'array' or jsonb_array_length(p_valor) > 80
     or exists (select 1 from jsonb_array_elements(p_valor) x where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9:_-]{1,40}$') then
    raise exception 'valor' using errcode = '22023';
  end if;
  insert into public.preferencias (dono, dados, atualizado_em) values (public.ref_atual(), jsonb_build_object(p_chave, p_valor), now())
  on conflict (dono) do update set dados = public.preferencias.dados || excluded.dados, atualizado_em = now()
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.preferencia_gravar(text, jsonb) from public, anon;
grant execute on function public.preferencia_gravar(text, jsonb) to authenticated;
