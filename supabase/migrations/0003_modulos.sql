-- LEVÍSSIMA · módulos: Manutenção, Checklist de empilhadeiras, Uniformes e EPI e Estoque de garrafões
-- Cada módulo guarda os seus dados na tabela modulo_docs, separado dos dados de cargas (tabela docs).
-- Quem abre cada módulo é decidido pela senha mestre: cada senha leva no login a lista dos módulos
-- que pode usar ("manutencao") ou gerenciar ("manutencao:gerir"). A senha mestre abre todos.

-- ---------- acessos por setor ----------
alter table public.acesso_senhas add column if not exists modulos text[] not null default '{}';
alter table public.acesso_senhas drop constraint if exists acesso_senhas_papel_check;
alter table public.acesso_senhas add constraint acesso_senhas_papel_check check (papel in ('mestre', 'equipe', 'motorista', 'setor'));

-- A pessoa logada pode abrir este módulo? (senha mestre, ou o módulo está na lista do login)
create or replace function public.pode_modulo(p_modulo text)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'mestre'
      or (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') in ('equipe', 'setor')
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?| array[p_modulo, p_modulo || ':gerir'], false));
$$;
grant execute on function public.pode_modulo(text) to authenticated;

-- ---------- dados dos módulos ----------
create table if not exists public.modulo_docs (
  modulo text not null check (modulo in ('manutencao', 'empilhadeiras', 'uniformes', 'garrafoes')),
  caminho text not null check (length(caminho) between 1 and 300),
  id text not null check (length(id) between 1 and 200),
  dados jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(),
  primary key (modulo, caminho, id)
);
alter table public.modulo_docs enable row level security;
revoke all on public.modulo_docs from public, anon;
grant select, insert, update, delete on public.modulo_docs to authenticated;
revoke truncate, references, trigger on public.modulo_docs from authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'modulo_le') then
    create policy "modulo_le" on public.modulo_docs for select to authenticated using (public.pode_modulo(modulo));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'modulo_grava') then
    create policy "modulo_grava" on public.modulo_docs for insert to authenticated with check (public.pode_modulo(modulo));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'modulo_altera') then
    create policy "modulo_altera" on public.modulo_docs for update to authenticated using (public.pode_modulo(modulo)) with check (public.pode_modulo(modulo));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'modulo_apaga') then
    create policy "modulo_apaga" on public.modulo_docs for delete to authenticated using (public.pode_modulo(modulo));
  end if;
end $$;

-- tempo real: as telas dos módulos se atualizam sozinhas
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'modulo_docs') then
    alter publication supabase_realtime add table public.modulo_docs;
  end if;
end $$;

-- junta dois JSON por dentro (objetos se misturam, o resto é trocado); {"__delete__": true} tira o campo
create or replace function public.jsonb_mesclar_mod(a jsonb, b jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  k text;
  v jsonb;
  r jsonb;
begin
  if b is null then return a; end if;
  if a is null or jsonb_typeof(a) <> 'object' or jsonb_typeof(b) <> 'object' then
    return public.jsonb_sem_marcas(b);
  end if;
  r := a;
  for k, v in select * from jsonb_each(b) loop
    if jsonb_typeof(v) = 'object' and v = '{"__delete__": true}'::jsonb then
      r := r - k;
    elsif r ? k and jsonb_typeof(r -> k) = 'object' and jsonb_typeof(v) = 'object' then
      r := jsonb_set(r, array[k], public.jsonb_mesclar_mod(r -> k, v));
    else
      r := jsonb_set(r, array[k], public.jsonb_sem_marcas(v));
    end if;
  end loop;
  return r;
end $$;

-- tira as marcas {"__delete__": true} de um JSON que vai ser gravado inteiro
create or replace function public.jsonb_sem_marcas(v jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  k text;
  x jsonb;
  r jsonb := '{}'::jsonb;
begin
  if v is null or jsonb_typeof(v) <> 'object' then return v; end if;
  for k, x in select * from jsonb_each(v) loop
    if not (jsonb_typeof(x) = 'object' and x = '{"__delete__": true}'::jsonb) then
      r := r || jsonb_build_object(k, public.jsonb_sem_marcas(x));
    end if;
  end loop;
  return r;
end $$;

-- grava um documento de um módulo (inteiro, ou misturando com o que já existe). Devolve como ficou.
create or replace function public.modulo_gravar(p_modulo text, p_caminho text, p_id text, p_dados jsonb, p_mesclar boolean default false)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  atual jsonb;
  novo jsonb;
begin
  select dados into atual from public.modulo_docs where modulo = p_modulo and caminho = p_caminho and id = p_id for update;
  if p_mesclar and atual is not null then
    novo := public.jsonb_mesclar_mod(atual, coalesce(p_dados, '{}'::jsonb));
  else
    novo := public.jsonb_sem_marcas(coalesce(p_dados, '{}'::jsonb));
  end if;
  insert into public.modulo_docs (modulo, caminho, id, dados, atualizado_em)
  values (p_modulo, p_caminho, p_id, novo, now())
  on conflict (modulo, caminho, id) do update set dados = excluded.dados, atualizado_em = now();
  return novo;
end $$;

-- muda só os campos enviados; o documento precisa existir
create or replace function public.modulo_atualizar(p_modulo text, p_caminho text, p_id text, p_dados jsonb)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  novo jsonb;
begin
  update public.modulo_docs
     set dados = public.jsonb_mesclar_mod(dados, coalesce(p_dados, '{}'::jsonb)), atualizado_em = now()
   where modulo = p_modulo and caminho = p_caminho and id = p_id
  returning dados into novo;
  if not found then
    raise exception 'Documento não existe: %/%/%', p_modulo, p_caminho, p_id using errcode = 'P0002';
  end if;
  return novo;
end $$;

revoke execute on function public.jsonb_mesclar_mod(jsonb, jsonb) from public, anon;
revoke execute on function public.jsonb_sem_marcas(jsonb) from public, anon;
revoke execute on function public.modulo_gravar(text, text, text, jsonb, boolean) from public, anon;
revoke execute on function public.modulo_atualizar(text, text, text, jsonb) from public, anon;
grant execute on function public.jsonb_mesclar_mod(jsonb, jsonb) to authenticated;
grant execute on function public.jsonb_sem_marcas(jsonb) to authenticated;
grant execute on function public.modulo_gravar(text, text, text, jsonb, boolean) to authenticated;
grant execute on function public.modulo_atualizar(text, text, text, jsonb) to authenticated;

-- ---------- trava curta (para numerar chamados e mexer no saldo de peças sem duas pessoas ao mesmo tempo) ----------
create table if not exists public.modulo_travas (
  modulo text not null,
  chave text not null,
  dono text not null,
  expira_em timestamptz not null,
  primary key (modulo, chave)
);
alter table public.modulo_travas enable row level security;
revoke all on public.modulo_travas from public, anon, authenticated;

create or replace function public.modulo_travar(p_modulo text, p_chave text, p_dono text, p_ms integer default 3000)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r public.modulo_travas;
  dur interval := make_interval(secs => least(greatest(coalesce(p_ms, 3000), 500), 60000) / 1000.0);
begin
  if not public.pode_modulo(p_modulo) then
    raise exception 'sem acesso ao módulo' using errcode = '42501';
  end if;
  insert into public.modulo_travas as t (modulo, chave, dono, expira_em)
  values (p_modulo, left(p_chave, 300), left(coalesce(p_dono, ''), 100), now() + dur)
  on conflict (modulo, chave) do update set dono = excluded.dono, expira_em = excluded.expira_em
    where t.expira_em < now() or t.dono = excluded.dono
  returning * into r;
  if found then
    return jsonb_build_object('acquired', true, 'expiresAt', r.expira_em);
  end if;
  select * into r from public.modulo_travas where modulo = p_modulo and chave = left(p_chave, 300);
  return jsonb_build_object('acquired', false, 'expiresAt', r.expira_em);
end $$;

create or replace function public.modulo_soltar(p_modulo text, p_chave text, p_dono text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.pode_modulo(p_modulo) then
    raise exception 'sem acesso ao módulo' using errcode = '42501';
  end if;
  update public.modulo_travas set expira_em = now() - interval '1 second'
   where modulo = p_modulo and chave = left(p_chave, 300) and dono = p_dono;
  return found;
end $$;

revoke execute on function public.modulo_travar(text, text, text, integer) from public, anon;
revoke execute on function public.modulo_soltar(text, text, text) from public, anon;
grant execute on function public.modulo_travar(text, text, text, integer) to authenticated;
grant execute on function public.modulo_soltar(text, text, text) to authenticated;

-- ---------- checklist de empilhadeira → chamado na Manutenção ----------
-- Quem faz o checklist (mesmo sem acesso ao módulo Manutenção) abre um chamado interno para a máquina própria.
-- O banco monta o chamado com campos conferidos; só o que vem do checklist entra.
create or replace function public.empilhadeira_abrir_chamado(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  n integer;
  maxn integer;
  cont jsonb;
  novo_id text;
  agora bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  prio integer := least(greatest(coalesce((p ->> 'prioridade')::integer, 3), 1), 4);
  tipo text := left(coalesce(nullif(p ->> 'tipo', ''), 'Segurança'), 40);
  nome text := left(coalesce(p ->> 'nome', ''), 80);
  maquina text := left(coalesce(nullif(p ->> 'maquina', ''), 'Empilhadeira'), 120);
  tag text := left(coalesce(p ->> 'tag', ''), 40);
  descr text := left(coalesce(p ->> 'descricao', ''), 3000);
  ck text := left(coalesce(p ->> 'checklistId', ''), 120);
  doc jsonb;
begin
  if not public.pode_modulo('empilhadeiras') then
    raise exception 'sem acesso ao módulo' using errcode = '42501';
  end if;
  if descr = '' then
    raise exception 'descrição vazia' using errcode = '22023';
  end if;
  insert into public.modulo_docs (modulo, caminho, id, dados) values ('manutencao', 'config', 'contador', '{"chamado": 0}')
  on conflict do nothing;
  select dados into cont from public.modulo_docs where modulo = 'manutencao' and caminho = 'config' and id = 'contador' for update;
  select coalesce(max(floor((d.dados ->> 'n')::numeric)), 0) into maxn
    from public.modulo_docs d
   where d.modulo = 'manutencao' and d.caminho = 'chamados' and jsonb_typeof(d.dados -> 'n') = 'number';
  n := greatest(coalesce(floor((cont ->> 'chamado')::numeric)::integer, 0), maxn) + 1;
  update public.modulo_docs set dados = jsonb_set(coalesce(dados, '{}'::jsonb), '{chamado}', to_jsonb(n)), atualizado_em = now()
   where modulo = 'manutencao' and caminho = 'config' and id = 'contador';
  novo_id := 'emp' || replace(gen_random_uuid()::text, '-', '');
  doc := jsonb_build_object(
    'n', n, 'linha', 'UTIL', 'equipId', null, 'equipNome', maquina, 'equipTag', tag, 'equipTipo', 'Empilhadeira',
    'prioridade', prio, 'parada', false, 'tipo', tipo, 'descricao', descr,
    'solicitante', jsonb_build_object('nome', nome, 'setor', 'Operação'),
    'abertoEm', agora, 'abertoPorId', null, 'status', 'aberto', 'tecnico', '', 'inicioEm', null, 'pausas', '[]'::jsonb,
    'fechadoEm', null, 'solucao', null, 'reaberturas', 0,
    'origem', jsonb_build_object('tipo', 'checklist-empilhadeira', 'id', ck),
    'atualizadoEm', agora,
    'eventos', jsonb_build_array(jsonb_build_object('t', agora, 'tipo', 'abertura', 'por', nome,
      'texto', 'Chamado aberto pelo checklist da empilhadeira ' || maquina || case when nome <> '' then ' (operador: ' || nome || ')' else '' end))
  );
  insert into public.modulo_docs (modulo, caminho, id, dados) values ('manutencao', 'chamados', novo_id, doc);
  return jsonb_build_object('id', novo_id, 'n', n);
end $$;

-- situação dos chamados abertos pelo checklist (só número, situação e técnico)
create or replace function public.empilhadeira_chamados(p_ids text[])
returns table (chamado_id text, n integer, status text, fechado_em bigint, tecnico text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.id, floor((d.dados ->> 'n')::numeric)::integer, d.dados ->> 'status',
         case when jsonb_typeof(d.dados -> 'fechadoEm') = 'number' then (d.dados ->> 'fechadoEm')::numeric::bigint end,
         coalesce(d.dados ->> 'tecnico', '')
    from public.modulo_docs d
   where public.pode_modulo('empilhadeiras')
     and d.modulo = 'manutencao' and d.caminho = 'chamados' and d.id = any(p_ids[1:200])
     and jsonb_typeof(d.dados -> 'n') = 'number';
$$;

revoke execute on function public.empilhadeira_abrir_chamado(jsonb) from public, anon;
revoke execute on function public.empilhadeira_chamados(text[]) from public, anon;
grant execute on function public.empilhadeira_abrir_chamado(jsonb) to authenticated;
grant execute on function public.empilhadeira_chamados(text[]) to authenticated;
