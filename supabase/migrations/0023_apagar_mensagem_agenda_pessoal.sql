-- LEVÍSSIMA · 0023: apagar mensagem do chat e agenda individual (pedidos de 20/10/2026).
--
-- * Apagar mensagem (Chat e Solicitações): cada um apaga a PRÓPRIA mensagem até 1 hora depois de enviar; a senha mestre
--   (ref 'mestre', o Nicolas) apaga qualquer mensagem das conversas dela, a qualquer momento. O texto some do banco
--   (fica "(mensagem apagada)", com quem apagou e quando). Só pela função chat_apagar.
-- * Minha agenda: compromissos de cada pessoa com acesso próprio ao app (senha mestre, diretoria e escritório). Só o
--   dono e as pessoas que ele incluiu leem o compromisso; ele aparece na agenda de quem foi incluído, que recebe o aviso
--   (vistos = quem já viu). Tipo trabalho ou pessoal. Gravação só pelas funções: compromisso_salvar (dono),
--   compromisso_cancelar (dono), compromisso_sair (quem foi incluído tira da própria agenda), compromisso_visto.

-- ---------- apagar mensagem ----------
alter table public.chat_msgs add column if not exists apagada boolean not null default false;
alter table public.chat_msgs add column if not exists apagada_em timestamptz;
alter table public.chat_msgs add column if not exists apagada_por text;

create or replace function public.chat_apagar(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  select * into r from public.chat_msgs m where m.id = p_id and (m.de = v_eu or m.para = v_eu) for update;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  if r.apagada then return to_jsonb(r); end if;
  if not (v_eu = 'mestre' or (r.de = v_eu and r.criado_em > now() - interval '1 hour')) then
    raise exception 'prazo' using errcode = '42501';
  end if;
  update public.chat_msgs m set apagada = true, apagada_em = now(), apagada_por = v_eu, texto = '(mensagem apagada)', lida = true, resolvido = null
   where m.id = p_id returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_apagar(bigint) from public, anon;
grant execute on function public.chat_apagar(bigint) to authenticated;

-- ---------- agenda individual ----------
create table if not exists public.compromissos (
  id bigint generated always as identity primary key,
  dono text not null,
  dono_nome text not null default '',
  titulo text not null check (length(titulo) between 1 and 120),
  data date not null,
  inicio time,
  fim time,
  tipo text not null default 'trabalho' check (tipo in ('trabalho', 'pessoal')),
  local text not null default '' check (length(local) <= 120),
  obs text not null default '' check (length(obs) <= 500),
  participantes text[] not null default '{}',
  participantes_nomes jsonb not null default '{}'::jsonb,
  vistos text[] not null default '{}',
  saiu text[] not null default '{}',
  cancelado boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists compromissos_dono_idx on public.compromissos (dono, data);
create index if not exists compromissos_part_idx on public.compromissos using gin (participantes);
alter table public.compromissos enable row level security;
revoke all on public.compromissos from public, anon, authenticated;
grant select on public.compromissos to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'compromissos' and policyname = 'compromisso_le_0023') then
    create policy compromisso_le_0023 on public.compromissos for select to authenticated
      using ((select public.chat_pode_0019()) and (dono = (select public.ref_atual()) or (select public.ref_atual()) = any (participantes)));
  end if;
end $$;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'compromissos') then
    alter publication supabase_realtime add table public.compromissos;
  end if;
end $$;

-- cria (p_id nulo) ou altera (só o dono) um compromisso. p: { titulo, data, inicio, fim, tipo, local, obs, participantes[] }
create or replace function public.compromisso_salvar(p_id bigint, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_tit text := btrim(coalesce(p ->> 'titulo', ''));
  v_data date;
  v_ini time;
  v_fim time;
  v_tipo text := coalesce(nullif(p ->> 'tipo', ''), 'trabalho');
  v_part text[];
  v_nomes jsonb;
  antes public.compromissos;
  r public.compromissos;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_tit = '' or length(v_tit) > 120 then raise exception 'titulo' using errcode = '22023'; end if;
  begin
    v_data := (p ->> 'data')::date;
    v_ini := nullif(p ->> 'inicio', '')::time;
    v_fim := nullif(p ->> 'fim', '')::time;
  exception when others then raise exception 'data' using errcode = '22023';
  end;
  if v_data is null or (v_ini is not null and v_fim is not null and v_fim <= v_ini) then raise exception 'data' using errcode = '22023'; end if;
  if v_tipo not in ('trabalho', 'pessoal') then raise exception 'tipo' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct x), '{}') into v_part
    from jsonb_array_elements_text(coalesce(p -> 'participantes', '[]'::jsonb)) x
   where x <> v_eu and public.chat_destino_ok_0019(x);
  if array_length(v_part, 1) > 30 then raise exception 'participantes' using errcode = '22023'; end if;
  select coalesce(jsonb_object_agg(s.ref, s.nome), '{}'::jsonb) into v_nomes from public.acesso_senhas s where s.ref = any (v_part);
  if p_id is null then
    insert into public.compromissos (dono, dono_nome, titulo, data, inicio, fim, tipo, local, obs, participantes, participantes_nomes)
    values (v_eu, public.nome_atual(), v_tit, v_data, v_ini, v_fim, v_tipo, left(btrim(coalesce(p ->> 'local', '')), 120), left(btrim(coalesce(p ->> 'obs', '')), 500), v_part, v_nomes)
    returning * into r;
  else
    select * into antes from public.compromissos c where c.id = p_id and c.dono = v_eu for update;
    if antes.id is null then raise exception 'permissao' using errcode = '42501'; end if;
    update public.compromissos c set titulo = v_tit, data = v_data, inicio = v_ini, fim = v_fim, tipo = v_tipo,
           local = left(btrim(coalesce(p ->> 'local', '')), 120), obs = left(btrim(coalesce(p ->> 'obs', '')), 500),
           participantes = v_part, participantes_nomes = v_nomes, cancelado = false, atualizado_em = now(),
           -- mudou dia, hora ou título: quem foi incluído recebe o aviso de novo
           vistos = case when antes.data is distinct from v_data or antes.inicio is distinct from v_ini or antes.titulo is distinct from v_tit
                         then '{}' else array(select unnest(antes.vistos) intersect select unnest(v_part)) end,
           saiu = array(select unnest(antes.saiu) intersect select unnest(v_part))
     where c.id = p_id returning * into r;
  end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.compromisso_salvar(bigint, jsonb) from public, anon;
grant execute on function public.compromisso_salvar(bigint, jsonb) to authenticated;

-- o dono cancela (quem foi incluído vê "cancelado" e recebe o aviso)
create or replace function public.compromisso_cancelar(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.compromissos;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  update public.compromissos c set cancelado = true, vistos = '{}', atualizado_em = now()
   where c.id = p_id and c.dono = public.ref_atual() returning * into r;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.compromisso_cancelar(bigint) from public, anon;
grant execute on function public.compromisso_cancelar(bigint) to authenticated;

-- quem foi incluído tira o compromisso da própria agenda
create or replace function public.compromisso_sair(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_eu text := public.ref_atual(); r public.compromissos;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  update public.compromissos c set saiu = array(select distinct unnest(c.saiu || v_eu)), vistos = array(select distinct unnest(c.vistos || v_eu)), atualizado_em = now()
   where c.id = p_id and v_eu = any (c.participantes) returning * into r;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.compromisso_sair(bigint) from public, anon;
grant execute on function public.compromisso_sair(bigint) to authenticated;

-- quem foi incluído já viu o aviso
create or replace function public.compromisso_visto(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_eu text := public.ref_atual(); n int;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  update public.compromissos c set vistos = array(select distinct unnest(c.vistos || v_eu))
   where c.id = any (p_ids) and v_eu = any (c.participantes) and not (v_eu = any (c.vistos));
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.compromisso_visto(bigint[]) from public, anon;
grant execute on function public.compromisso_visto(bigint[]) to authenticated;
