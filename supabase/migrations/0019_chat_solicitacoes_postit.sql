-- LEVÍSSIMA · 0019: chat entre usuários, Solicitações (chat direto com a senha mestre), post-it individual
-- e datas comemorativas (pedidos de 19/10/2026).
--
-- * chat_msgs: todas as mensagens.
--     tipo 'chat' → conversa entre duas pessoas com acesso ao app (conversa = "<ref menor>|<ref maior>");
--     tipo 'sol'  → Solicitações: conversa = ref de quem pediu; as mensagens vão de quem pediu para 'mestre'
--                   (a senha mestre, o Nicolas) e as respostas, de 'mestre' para quem pediu. Cada resposta leva a
--                   pergunta "Resolveu?" (resolvido: null = sem resposta, true/false), que quem pediu assinala.
--   Cada um só lê as mensagens em que é o remetente ou o destinatário (a diretoria, que entra como mestre, NÃO lê as
--   Solicitações dos outros: só a ref 'mestre'). Ninguém grava direto: só pelas funções abaixo, que carimbam
--   remetente e nome a partir do login (não dá para mandar em nome de outro).
-- * postits: o lembrete da tela inicial, um por acesso; só o dono lê e grava.
-- * datas-comemorativas (coleção da tabela docs): lista de datas e mensagens; todos do escritório leem,
--   só a senha mestre grava.
-- Quem usa: senha mestre, diretoria e as pessoas com acesso próprio (papéis mestre e equipe).

-- ---------- mensagens ----------
create table if not exists public.chat_msgs (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('chat', 'sol')),
  conversa text not null check (length(conversa) between 1 and 200),
  de text not null,
  de_nome text not null default '',
  para text not null,
  texto text not null check (length(texto) between 1 and 2000),
  criado_em timestamptz not null default now(),
  lida boolean not null default false,
  lida_em timestamptz,
  resolvido boolean,
  resolvido_em timestamptz
);
create index if not exists chat_msgs_de_idx on public.chat_msgs (de, id);
create index if not exists chat_msgs_para_idx on public.chat_msgs (para, id);
create index if not exists chat_msgs_conversa_idx on public.chat_msgs (tipo, conversa, id);
alter table public.chat_msgs enable row level security;
revoke all on public.chat_msgs from public, anon, authenticated;
grant select on public.chat_msgs to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'chat_msgs' and policyname = 'chat_le_0019') then
    create policy chat_le_0019 on public.chat_msgs for select to authenticated
      using ((select public.papel_atual()) in ('mestre', 'equipe') and (select public.ref_atual()) <> ''
             and (de = (select public.ref_atual()) or para = (select public.ref_atual())));
  end if;
end $$;
-- tempo real (as mensagens chegam na hora; o Supabase entrega só o que a regra acima deixa ler)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_msgs') then
    alter publication supabase_realtime add table public.chat_msgs;
  end if;
end $$;

-- quem pode usar: papel mestre ou equipe, com ref
create or replace function public.chat_pode_0019()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select public.papel_atual() in ('mestre', 'equipe') and public.ref_atual() <> ''; $$;
revoke execute on function public.chat_pode_0019() from public, anon;
grant execute on function public.chat_pode_0019() to authenticated;

-- ref de uma pessoa que pode receber mensagem (acesso ativo de senha mestre, diretoria ou pessoa do escritório)
create or replace function public.chat_destino_ok_0019(p_ref text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.acesso_senhas s
                  where s.ref = p_ref and s.papel in ('mestre', 'diretoria', 'equipe') and s.nome !~* 'desativad');
$$;
revoke execute on function public.chat_destino_ok_0019(text) from public, anon, authenticated;

-- lista de pessoas para conversar (só ref e nome; sem nada da senha)
create or replace function public.chat_pessoas()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ref', s.ref, 'nome', s.nome) order by s.nome)
                     from public.acesso_senhas s
                    where s.papel in ('mestre', 'diretoria', 'equipe') and s.nome !~* 'desativad'
                      and s.ref <> public.ref_atual()), '[]'::jsonb);
end $$;
revoke execute on function public.chat_pessoas() from public, anon;
grant execute on function public.chat_pessoas() to authenticated;

-- limite contra enxurrada: 30 mensagens por minuto por acesso
create or replace function public.chat_limite_0019()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (select count(*) from public.chat_msgs m where m.de = public.ref_atual() and m.criado_em > now() - interval '1 minute') >= 30 then
    raise exception 'muitas mensagens' using errcode = '54000';
  end if;
end $$;
revoke execute on function public.chat_limite_0019() from public, anon, authenticated;

-- chat: manda uma mensagem para outra pessoa
create or replace function public.chat_enviar(p_para text, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  if p_para is null or p_para = v_eu or not public.chat_destino_ok_0019(p_para) then raise exception 'destino' using errcode = '22023'; end if;
  perform public.chat_limite_0019();
  insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto)
  values ('chat', least(v_eu, p_para) || '|' || greatest(v_eu, p_para), v_eu, public.nome_atual(), p_para, v_txt)
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_enviar(text, text) from public, anon;
grant execute on function public.chat_enviar(text, text) to authenticated;

-- Solicitações: quem pede escreve para a senha mestre; a senha mestre responde na conversa de quem pediu
create or replace function public.sol_enviar(p_texto text, p_conversa text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  perform public.chat_limite_0019();
  if v_eu = 'mestre' then
    if p_conversa is null or p_conversa = 'mestre' or not public.chat_destino_ok_0019(p_conversa) then raise exception 'destino' using errcode = '22023'; end if;
    insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto)
    values ('sol', p_conversa, 'mestre', public.nome_atual(), p_conversa, v_txt) returning * into r;
  else
    insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto)
    values ('sol', v_eu, v_eu, public.nome_atual(), 'mestre', v_txt) returning * into r;
  end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.sol_enviar(text, text) from public, anon;
grant execute on function public.sol_enviar(text, text) to authenticated;

-- "Resolveu?": quem pediu (ou a própria senha mestre) assinala sim ou não numa resposta da senha mestre
create or replace function public.sol_resolvido(p_id bigint, p_resolvido boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() or p_resolvido is null then raise exception 'permissao' using errcode = '42501'; end if;
  update public.chat_msgs m set resolvido = p_resolvido, resolvido_em = now()
   where m.id = p_id and m.tipo = 'sol' and m.de = 'mestre' and (m.para = v_eu or v_eu = 'mestre')
  returning * into r;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.sol_resolvido(bigint, boolean) from public, anon;
grant execute on function public.sol_resolvido(bigint, boolean) to authenticated;

-- marca como lidas as mensagens recebidas numa conversa
create or replace function public.chat_lidas(p_tipo text, p_conversa text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  update public.chat_msgs m set lida = true, lida_em = now()
   where m.para = public.ref_atual() and m.tipo = p_tipo and m.conversa = p_conversa and not m.lida;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.chat_lidas(text, text) from public, anon;
grant execute on function public.chat_lidas(text, text) to authenticated;

-- ---------- post-it da tela inicial ----------
create table if not exists public.postits (
  dono text primary key,
  texto text not null default '' check (length(texto) <= 1000),
  atualizado_em timestamptz not null default now()
);
alter table public.postits enable row level security;
revoke all on public.postits from public, anon, authenticated;
grant select on public.postits to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'postits' and policyname = 'postit_dono_0019') then
    create policy postit_dono_0019 on public.postits for select to authenticated
      using ((select public.ref_atual()) <> '' and dono = (select public.ref_atual()));
  end if;
end $$;
create or replace function public.postit_gravar(p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_txt text := left(coalesce(p_texto, ''), 1000);
  r public.postits;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  insert into public.postits (dono, texto, atualizado_em) values (public.ref_atual(), v_txt, now())
  on conflict (dono) do update set texto = excluded.texto, atualizado_em = now()
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.postit_gravar(text) from public, anon;
grant execute on function public.postit_gravar(text) to authenticated;

-- ---------- datas comemorativas: só a senha mestre grava ----------
create or replace function public.colecao_grava_mestre_0019(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('datas-comemorativas'); $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_grava_0019') then
    create policy mestre_grava_0019 on public.docs as restrictive for insert to authenticated
      with check (not public.colecao_grava_mestre_0019(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_altera_0019') then
    create policy mestre_altera_0019 on public.docs as restrictive for update to authenticated
      using (not public.colecao_grava_mestre_0019(colecao) or (select public.papel_atual()) = 'mestre')
      with check (not public.colecao_grava_mestre_0019(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_apaga_0019') then
    create policy mestre_apaga_0019 on public.docs as restrictive for delete to authenticated
      using (not public.colecao_grava_mestre_0019(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;
