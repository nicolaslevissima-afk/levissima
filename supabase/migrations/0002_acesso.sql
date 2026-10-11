-- LEVÍSSIMA · acesso protegido pelo próprio banco
-- Só entra quem digitou uma senha válida (mestre, equipe do escritório ou motorista).
-- As senhas ficam aqui só como hash (bcrypt) e nunca podem ser lidas pelo app.
-- A conferência da senha é feita pela função "acesso" (Edge Function), com a chave de serviço.
-- (a remoção de uma senha e a limpeza das tentativas antigas são feitas pela função, com a chave de serviço)

create extension if not exists pgcrypto with schema extensions;

-- ---------- senhas, tentativas e segredo interno (nada disso é visível para o app) ----------
create table if not exists public.acesso_senhas (
  ref text primary key,                       -- 'mestre' | 'equipe' | 'motorista:<id>'
  papel text not null check (papel in ('mestre', 'equipe', 'motorista')),
  nome text not null default '',
  hash text not null,
  usuario uuid,                               -- usuário do Supabase Auth ligado a esta senha
  atualizado_em timestamptz not null default now()
);
create table if not exists public.acesso_tentativas (
  id bigserial primary key,
  origem text not null default '',
  ok boolean not null,
  em timestamptz not null default now()
);
create table if not exists public.acesso_segredo (
  id int primary key default 1 check (id = 1),
  segredo text not null default encode(extensions.gen_random_bytes(32), 'hex')
);
insert into public.acesso_segredo (id) values (1) on conflict do nothing;

alter table public.acesso_senhas enable row level security;
alter table public.acesso_tentativas enable row level security;
alter table public.acesso_segredo enable row level security;
revoke all on public.acesso_senhas, public.acesso_tentativas, public.acesso_segredo from public, anon, authenticated;
revoke all on sequence public.acesso_tentativas_id_seq from public, anon, authenticated;

-- ---------- funções usadas só pela Edge Function "acesso" (chave de serviço) ----------
-- Compara a senha com o hash sem nunca quebrar (um hash inválido numa linha não pode travar o login de todos).
create or replace function public.senha_confere(p_senha text, p_hash text)
returns boolean
language plpgsql
immutable
set search_path = public, extensions, pg_temp
as $$
begin
  return p_hash is not null and p_hash = extensions.crypt(coalesce(p_senha, ''), p_hash);
exception when others then
  return false;
end $$;

-- Confere a senha. Mais de 20 erros em 10 minutos vindos do mesmo lugar (ou 100 no total): bloqueia por um tempo.
create or replace function public.acesso_conferir(p_senha text, p_origem text default '')
returns table (ref text, papel text, nome text, usuario uuid)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  erros int;
  total int;
begin
  select count(*) filter (where t.origem = coalesce(p_origem, '')), count(*) into erros, total
    from public.acesso_tentativas t
   where not t.ok and t.em > now() - interval '10 minutes';
  if erros >= 20 or total >= 100 then
    raise exception 'muitas tentativas' using errcode = 'P0429';
  end if;
  return query
    select s.ref, s.papel, s.nome, s.usuario from public.acesso_senhas s
     where public.senha_confere(p_senha, s.hash)
     limit 1;
  insert into public.acesso_tentativas (origem, ok) values (coalesce(p_origem, ''), found);
end $$;
create index if not exists acesso_tentativas_em on public.acesso_tentativas (em);

-- Cria ou troca uma senha. A mesma senha não pode servir para duas pessoas.
create or replace function public.acesso_definir(p_ref text, p_papel text, p_nome text, p_senha text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'senha curta' using errcode = 'P0422';
  end if;
  if exists (select 1 from public.acesso_senhas s where s.ref <> p_ref and public.senha_confere(p_senha, s.hash)) then
    raise exception 'senha em uso' using errcode = 'P0409';
  end if;
  insert into public.acesso_senhas (ref, papel, nome, hash)
  values (p_ref, p_papel, coalesce(p_nome, ''), extensions.crypt(p_senha, extensions.gen_salt('bf', 8)))
  on conflict (ref) do update
     set papel = excluded.papel, nome = excluded.nome, hash = excluded.hash, atualizado_em = now();
end $$;

create or replace function public.acesso_ligar_usuario(p_ref text, p_usuario uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$ update public.acesso_senhas set usuario = p_usuario where ref = p_ref; $$;

create or replace function public.acesso_lista()
returns table (ref text, papel text, nome text, atualizado_em timestamptz)
language sql
security definer
set search_path = public, pg_temp
as $$ select s.ref, s.papel, s.nome, s.atualizado_em from public.acesso_senhas s order by s.ref; $$;

create or replace function public.acesso_segredo_ler()
returns text
language sql
security definer
set search_path = public, pg_temp
as $$ select segredo from public.acesso_segredo where id = 1; $$;

revoke execute on function public.senha_confere(text, text) from public, anon, authenticated;
grant execute on function public.senha_confere(text, text) to service_role;
revoke execute on function public.acesso_conferir(text, text) from public, anon, authenticated;
revoke execute on function public.acesso_definir(text, text, text, text) from public, anon, authenticated;
revoke execute on function public.acesso_ligar_usuario(text, uuid) from public, anon, authenticated;
revoke execute on function public.acesso_lista() from public, anon, authenticated;
revoke execute on function public.acesso_segredo_ler() from public, anon, authenticated;
grant execute on function public.acesso_conferir(text, text) to service_role;
grant execute on function public.acesso_definir(text, text, text, text) to service_role;
grant execute on function public.acesso_ligar_usuario(text, uuid) to service_role;
grant execute on function public.acesso_lista() to service_role;
grant execute on function public.acesso_segredo_ler() to service_role;

-- ---------- quem está usando o app (vem do login, gravado no token) ----------
create or replace function public.papel_atual()
returns text
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', ''); $$;
grant execute on function public.papel_atual() to authenticated;

-- ---------- dados do app: só para quem entrou; pesquisas só para a senha mestre ----------
-- (cada política só é criada se ainda não existir: o arquivo pode ser rodado de novo sem erro)
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'le') then
    create policy "le" on public.docs for select to authenticated
      using ((select public.papel_atual()) in ('mestre', 'equipe', 'motorista')
             and (colecao <> 'pesquisas' or (select public.papel_atual()) = 'mestre'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'grava') then
    create policy "grava" on public.docs for insert to authenticated
      with check ((select public.papel_atual()) in ('mestre', 'equipe', 'motorista'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'altera') then
    create policy "altera" on public.docs for update to authenticated
      using ((select public.papel_atual()) in ('mestre', 'equipe', 'motorista')
             and (colecao <> 'pesquisas' or (select public.papel_atual()) = 'mestre'))
      with check ((select public.papel_atual()) in ('mestre', 'equipe', 'motorista'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'apaga') then
    create policy "apaga" on public.docs for delete to authenticated
      using ((select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
end $$;

revoke all on public.docs from public, anon;
grant select, insert, update, delete on public.docs to authenticated;
revoke truncate, references, trigger on public.docs from authenticated;

revoke execute on function public.jsonb_mesclar(jsonb, jsonb) from public, anon;
revoke execute on function public.doc_gravar(text, text, jsonb, boolean, jsonb) from public, anon;
revoke execute on function public.doc_atualizar(text, text, jsonb) from public, anon;
revoke execute on function public.docs_lote(jsonb) from public, anon;
grant execute on function public.jsonb_mesclar(jsonb, jsonb) to authenticated;
grant execute on function public.doc_gravar(text, text, jsonb, boolean, jsonb) to authenticated;
grant execute on function public.doc_atualizar(text, text, jsonb) to authenticated;
grant execute on function public.docs_lote(jsonb) to authenticated;

-- Pesquisa de satisfação: quem responde só grava (não pode ler nem trocar respostas depois).
create or replace function public.pesquisa_gravar(p_id text, p_dados jsonb)
returns boolean
language plpgsql
set search_path = public, pg_temp
as $$
begin
  insert into public.docs (colecao, id, data, atualizado_em) values ('pesquisas', p_id, coalesce(p_dados, '{}'::jsonb), now());
  return true;
exception when unique_violation then
  return false; -- já respondida: fica a primeira resposta
end $$;
revoke execute on function public.pesquisa_gravar(text, jsonb) from public, anon;
grant execute on function public.pesquisa_gravar(text, jsonb) to authenticated;
