-- LEVÍSSIMA · 0037: senhas de acesso fortes, aparelhos, sair de todos os aparelhos e segundo fator (29/10/2026).
--
-- * acesso_definir: senha nova com pelo menos 8 caracteres e sem as fáceis (sequências, repetidas, datas, comuns).
--   As senhas que já existem continuam valendo.
-- * acesso_conferir: 10 erros em 15 minutos vindos do mesmo lugar bloqueiam esse lugar; 300 erros no total em 15
--   minutos (ataque espalhado) bloqueiam por alguns minutos. Os bloqueios viram aviso para a senha mestre.
-- * acesso_aparelhos: em que aparelhos cada senha entrou (a função "acesso" avisa a senha mestre de aparelho novo).
-- * acesso_revogacoes + papel_atual: "Sair de todos os aparelhos" (e a troca de senha) derruba na hora os logins
--   abertos daquela senha — o token emitido antes da revogação deixa de valer em todas as regras do banco.
--   pode_modulo, pode_liberar_carga, ve_canhotos e ve_aba_0033 passam a usar papel_atual (valem igual à revogação).
-- * acesso_totp: o segundo fator da senha mestre (código do Google Authenticator e códigos de emergência).
-- Nenhuma dessas tabelas tem regra de leitura: só a função "acesso" (chave de serviço) mexe nelas.

create table if not exists public.acesso_revogacoes (
  ref text primary key,
  em timestamptz not null default now(),
  por text not null default ''
);
alter table public.acesso_revogacoes enable row level security;
revoke all on public.acesso_revogacoes from public, anon, authenticated;

create table if not exists public.acesso_aparelhos (
  ref text not null,
  aparelho text not null,
  descricao text not null default '',
  origem text not null default '',
  primeiro_em timestamptz not null default now(),
  ultimo_em timestamptz not null default now(),
  primary key (ref, aparelho)
);
alter table public.acesso_aparelhos enable row level security;
revoke all on public.acesso_aparelhos from public, anon, authenticated;

create table if not exists public.acesso_totp (
  ref text primary key,
  segredo text not null,
  ativo boolean not null default false,
  ultimo_passo bigint not null default 0,
  recuperacao text[] not null default '{}',
  criado_em timestamptz not null default now(),
  ativado_em timestamptz
);
alter table public.acesso_totp enable row level security;
revoke all on public.acesso_totp from public, anon, authenticated;

-- papel do token, a não ser que a senha tenha sido revogada depois que o token foi emitido
create or replace function public.papel_atual()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when exists (select 1 from public.acesso_revogacoes r
                            where r.ref = coalesce(auth.jwt() -> 'app_metadata' ->> 'ref', '')
                              and r.em > to_timestamp(coalesce(nullif(auth.jwt() ->> 'iat', '')::double precision, 0)))
              then '' else coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') end;
$$;

create or replace function public.pode_modulo(p_modulo text)
returns boolean language sql stable set search_path = public, pg_temp
as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() in ('equipe', 'setor')
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?| array[p_modulo, p_modulo || ':gerir'], false));
$$;

create or replace function public.pode_liberar_carga()
returns boolean language sql stable set search_path = public, pg_temp
as $$
  select (public.papel_atual() = 'mestre' and not public.so_inclui())
      or (public.papel_atual() = 'equipe' and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'liberar_carga', false));
$$;

create or replace function public.ve_canhotos()
returns boolean language sql stable set search_path = public, pg_temp
as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() = 'equipe' and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'canhotos', false));
$$;

create or replace function public.ve_aba_0033(p_aba text)
returns boolean language sql stable set search_path = public, pg_temp
as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() = 'equipe'
          and (not coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'abas', false)
               or coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? ('aba:' || p_aba), false)));
$$;

-- motivo de a senha ser fraca (ou null quando serve)
create or replace function public.senha_fraca_0037(p_senha text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  s text := lower(coalesce(p_senha, ''));
  n text := regexp_replace(lower(coalesce(p_senha, '')), '[^a-z0-9]', '', 'g');
begin
  if length(coalesce(p_senha, '')) < 8 then return 'curta'; end if;
  if s ~ '^(.)\1+$' then return 'repetida'; end if;
  if position(s in '01234567890123456789') > 0 or position(s in '98765432109876543210') > 0
     or position(s in 'abcdefghijklmnopqrstuvwxyz') > 0 or position(s in 'qwertyuiopasdfghjklzxcvbnm') > 0 then return 'sequencia'; end if;
  if s in ('12345678', '123456789', '1234567890', '87654321', '11223344', '12341234', '12121212', 'senha123', 'senha1234', 'password', 'password1',
           'qwerty123', 'abc12345', 'abcd1234', 'mudar123', 'mudar1234', 'admin123', 'teste123', 'brasil123', 'iloveyou') then return 'comum'; end if;
  if n ~ '^(levissima|senha|password|admin|mudar|teste|brasil)[0-9]*$' then return 'comum'; end if;
  if s ~ '^\d{2}[/.-]?\d{2}[/.-]?(\d{2}|\d{4})$' and substr(n, 1, 2)::int between 1 and 31 and substr(n, 3, 2)::int between 1 and 12 then return 'data'; end if;
  if s ~ '^(19|20)\d{2}[/.-]?\d{2}[/.-]?\d{2}$' then return 'data'; end if;
  return null;
end $$;

create or replace function public.acesso_definir(p_ref text, p_papel text, p_nome text, p_senha text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_motivo text := public.senha_fraca_0037(p_senha);
begin
  if v_motivo = 'curta' then
    raise exception 'senha curta' using errcode = 'P0422';
  elsif v_motivo is not null then
    raise exception 'senha fraca: %', v_motivo using errcode = 'P0422';
  end if;
  if exists (select 1 from public.acesso_senhas s where s.ref <> p_ref and public.senha_confere(p_senha, s.hash)) then
    raise exception 'senha em uso' using errcode = 'P0409';
  end if;
  insert into public.acesso_senhas (ref, papel, nome, hash)
  values (p_ref, p_papel, coalesce(p_nome, ''), extensions.crypt(p_senha, extensions.gen_salt('bf', 8)))
  on conflict (ref) do update
     set papel = excluded.papel, nome = excluded.nome, hash = excluded.hash, atualizado_em = now();
end $$;

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
   where not t.ok and t.em > now() - interval '15 minutes';
  if erros >= 10 or total >= 300 then
    raise exception 'muitas tentativas' using errcode = 'P0429';
  end if;
  return query
    select s.ref, s.papel, s.nome, s.usuario from public.acesso_senhas s
     where public.senha_confere(p_senha, s.hash)
     limit 1;
  insert into public.acesso_tentativas (origem, ok) values (coalesce(p_origem, ''), found);
  if not found then
    if erros + 1 = 10 then
      perform public.seguranca_registrar_0034('senha_tentativas', '', '', '10 senhas de acesso erradas em 15 minutos vindas do mesmo lugar: esse lugar ficou bloqueado por 15 minutos.', coalesce(p_origem, ''));
    end if;
    if total + 1 = 300 then
      perform public.seguranca_registrar_0034('senha_ataque', '', '', '300 senhas de acesso erradas em 15 minutos (possível ataque): o login ficou bloqueado por alguns minutos.', '');
    end if;
  end if;
end $$;

-- segundo fator: o "ticket" entre a senha mestre certa e o código fica em acesso_desafios (tipo 'segundo')
alter table public.acesso_desafios drop constraint if exists acesso_desafios_tipo_check;
alter table public.acesso_desafios add constraint acesso_desafios_tipo_check check (tipo = any (array['cadastro', 'entrar', 'segundo']));
-- (aplicada em partes: 0037a…0037e)
