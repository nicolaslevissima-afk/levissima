-- LEVÍSSIMA · 0034: senha de 4 números (PIN de assinatura) conferida no servidor (pedido de 29/10/2026).
--
-- Antes, o app baixava para o celular o hash SHA-256 (sem sal) do PIN de todos e conferia ali: com só 10.000
-- combinações, qualquer pessoa logada descobria todos os PINs em milissegundos. Agora:
-- * equipe_pins: HMAC-SHA256 do PIN com um segredo que só o banco conhece (pin_segredo). As duas tabelas não têm
--   nenhuma regra de leitura: ninguém lê pela API, só as funções abaixo (SECURITY DEFINER).
-- * pin_conferir(pin): diz de quem é o PIN (o app nunca recebe hash). 5 erros em 15 minutos bloqueiam aquele acesso
--   por 15 minutos; 10 erros em 24 horas bloqueiam até a senha mestre liberar. Tudo fica em pin_tentativas e os
--   bloqueios viram aviso em seguranca_eventos (só a senha mestre lê).
-- * PIN marcado "trocar" (exposto) não assina mais: a pessoa precisa de um PIN novo.
-- * O documento da equipe guarda só "temPin" e "pinTrocar"; o gatilho tira qualquer pinHash que um app antigo mande.
-- * pin_definir / pin_remover / pin_desbloquear: só a senha mestre (a diretoria, que só inclui, não).
-- * Pedido de senha feito pela própria pessoa (cadastro_pedir): o PIN fica em pin_pendentes até a aprovação
--   (pin_aprovar_cadastro). Os PINs que já existiam passam para equipe_pins sem ninguém precisar digitar de novo
--   (o HMAC é feito sobre o SHA-256 antigo). A 0035 liga o gatilho e tira o pinHash dos documentos, junto com a
--   versão do app que confere no servidor.
-- * Nada é apagado: PIN removido fica inativo (ativo = false), tentativa liberada fica marcada (liberado) e pedido
--   usado fica marcado (usado) — o histórico continua para conferência.
-- (aplicada em partes: 0034a…0034i)

create table if not exists public.pin_segredo (
  id int primary key default 1 check (id = 1),
  chave bytea not null
);
alter table public.pin_segredo enable row level security;
revoke all on public.pin_segredo from public, anon, authenticated;
insert into public.pin_segredo (id, chave) values (1, extensions.gen_random_bytes(32)) on conflict (id) do nothing;

create table if not exists public.equipe_pins (
  membro_id text primary key,
  hash text not null unique,
  trocar boolean not null default false,
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now(),
  por text not null default ''
);
alter table public.equipe_pins enable row level security;
revoke all on public.equipe_pins from public, anon, authenticated;

create table if not exists public.pin_pendentes (
  pedido_id text primary key,
  hash text not null,
  usado boolean not null default false,
  criado_em timestamptz not null default now()
);
alter table public.pin_pendentes enable row level security;
revoke all on public.pin_pendentes from public, anon, authenticated;

create table if not exists public.pin_tentativas (
  id bigserial primary key,
  em timestamptz not null default now(),
  usuario uuid,
  ref text not null default '',
  nome text not null default '',
  ok boolean not null,
  liberado boolean not null default false
);
create index if not exists pin_tentativas_usuario_em on public.pin_tentativas (usuario, em desc);
alter table public.pin_tentativas enable row level security;
revoke all on public.pin_tentativas from public, anon, authenticated;

-- avisos de segurança para a senha mestre (bloqueios, PIN trocado, tentativas de senha, aparelho novo...)
create table if not exists public.seguranca_eventos (
  id bigserial primary key,
  em timestamptz not null default now(),
  tipo text not null,
  ref text not null default '',
  nome text not null default '',
  detalhe text not null default '',
  origem text not null default '',
  visto boolean not null default false
);
create index if not exists seguranca_eventos_em on public.seguranca_eventos (em desc);
alter table public.seguranca_eventos enable row level security;
revoke all on public.seguranca_eventos from public, anon;
grant select on public.seguranca_eventos to authenticated;
grant update (visto) on public.seguranca_eventos to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'seguranca_eventos' and policyname = 'seguranca_le_0034') then
    create policy "seguranca_le_0034" on public.seguranca_eventos for select to authenticated
      using ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'seguranca_eventos' and policyname = 'seguranca_visto_0034') then
    create policy "seguranca_visto_0034" on public.seguranca_eventos for update to authenticated
      using ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui()))
      with check ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;

create or replace function public.seguranca_registrar_0034(p_tipo text, p_ref text, p_nome text, p_detalhe text, p_origem text default '')
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.seguranca_eventos (tipo, ref, nome, detalhe, origem)
  values (left(coalesce(p_tipo, ''), 40), left(coalesce(p_ref, ''), 120), left(coalesce(p_nome, ''), 120), left(coalesce(p_detalhe, ''), 500), left(coalesce(p_origem, ''), 80));
$$;
revoke execute on function public.seguranca_registrar_0034(text, text, text, text, text) from public, anon, authenticated;

-- hash guardado: HMAC-SHA256(SHA-256 do PIN em hexadecimal, segredo do banco)
create or replace function public.pin_hash_0034(p_sha text)
returns text
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select encode(extensions.hmac(convert_to(lower(coalesce(p_sha, '')), 'UTF8'), (select chave from public.pin_segredo where id = 1), 'sha256'), 'hex');
$$;
revoke execute on function public.pin_hash_0034(text) from public, anon, authenticated;

create or replace function public.pin_de_0034(p_pin text)
returns text
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$ select public.pin_hash_0034(encode(extensions.digest(coalesce(p_pin, ''), 'sha256'), 'hex')); $$;
revoke execute on function public.pin_de_0034(text) from public, anon, authenticated;

-- PIN fácil demais: todos iguais (1111) ou em sequência (1234, 4321, 0123, 9876...)
create or replace function public.pin_facil_0034(p_pin text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select p_pin ~ '^(\d)\1{3}$' or position(p_pin in '01234567890') > 0 or position(p_pin in '09876543210') > 0;
$$;

-- o documento da equipe nunca guarda o PIN: o gatilho tira pinHash (de app antigo) e marca se a pessoa tem PIN
create or replace function public.equipe_pin_guarda_0034()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tem boolean := false;
  v_trocar boolean := false;
begin
  if new.colecao = 'equipe' then
    select true, e.trocar into v_tem, v_trocar from public.equipe_pins e where e.membro_id = new.id and e.ativo;
    new.data := (coalesce(new.data, '{}'::jsonb) - 'pinHash' - 'pin')
      || jsonb_build_object('temPin', coalesce(v_tem, false), 'pinTrocar', coalesce(v_trocar, false));
  elsif new.colecao = 'cadastro-pedidos' then
    new.data := coalesce(new.data, '{}'::jsonb) - 'pinHash' - 'pin';
  end if;
  return new;
end $$;
revoke execute on function public.equipe_pin_guarda_0034() from public, anon, authenticated;
-- (o gatilho é ligado na 0035, junto com a versão nova do app)

create or replace function public.pin_tocar_membro_0034(p_membro text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$ update public.docs set data = data, atualizado_em = now() where colecao = 'equipe' and id = p_membro; $$;
revoke execute on function public.pin_tocar_membro_0034(text) from public, anon, authenticated;

-- De quem é este PIN? { ok, membro, trocar } ou { ok: false, bloqueado, minutos, mestre }
create or replace function public.pin_conferir(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_papel text := coalesce(public.papel_atual(), '');
  v_uid uuid := auth.uid();
  v_ref text := coalesce(public.ref_atual(), '');
  v_nome text := coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', '');
  v_err15 int; v_err24 int; v_ult timestamptz;
  v_membro text; v_trocar boolean;
begin
  if v_papel not in ('mestre', 'equipe', 'setor', 'motorista') or v_uid is null then raise exception 'permissao'; end if;
  select count(*) filter (where em > now() - interval '15 minutes'), count(*), max(em)
    into v_err15, v_err24, v_ult
    from public.pin_tentativas where usuario = v_uid and not ok and not liberado and em > now() - interval '24 hours';
  if v_err24 >= 10 then
    return jsonb_build_object('ok', false, 'bloqueado', true, 'mestre', true);
  end if;
  if v_err15 >= 5 then
    return jsonb_build_object('ok', false, 'bloqueado', true, 'minutos', greatest(1, ceil(extract(epoch from (v_ult + interval '15 minutes' - now())) / 60)::int));
  end if;
  if coalesce(p_pin, '') ~ '^\d{4}$' then
    select e.membro_id, e.trocar into v_membro, v_trocar from public.equipe_pins e where e.hash = public.pin_de_0034(p_pin) and e.ativo;
  end if;
  if v_membro is not null and v_trocar then
    -- PIN exposto: não assina, mas também não conta como tentativa errada
    return jsonb_build_object('ok', false, 'trocar', true, 'membro', v_membro);
  end if;
  insert into public.pin_tentativas (usuario, ref, nome, ok) values (v_uid, v_ref, v_nome, v_membro is not null);
  if v_membro is null then
    if v_err24 + 1 = 10 then
      perform public.seguranca_registrar_0034('pin_bloqueio_mestre', v_ref, v_nome, '10 senhas de 4 números erradas em 24 horas: acesso bloqueado para assinar até a senha mestre liberar.', '');
    elsif v_err15 + 1 = 5 then
      perform public.seguranca_registrar_0034('pin_bloqueio', v_ref, v_nome, '5 senhas de 4 números erradas em 15 minutos: bloqueado por 15 minutos.', '');
    end if;
    return jsonb_build_object('ok', false, 'restam', greatest(0, least(5 - (v_err15 + 1), 10 - (v_err24 + 1))));
  end if;
  return jsonb_build_object('ok', true, 'membro', v_membro, 'trocar', false);
end $$;
revoke execute on function public.pin_conferir(text) from public, anon;
grant execute on function public.pin_conferir(text) to authenticated;

create or replace function public.pin_e_mestre_0034()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(public.papel_atual(), '') = 'mestre' and not public.so_inclui(); $$;

-- Senha mestre define o PIN de alguém da equipe
create or replace function public.pin_definir(p_membro text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hash text;
  v_nome text;
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  select data ->> 'nome' into v_nome from public.docs where colecao = 'equipe' and id = p_membro;
  if v_nome is null then raise exception 'membro'; end if;
  if coalesce(p_pin, '') !~ '^\d{4}$' then raise exception 'pin_formato'; end if;
  if public.pin_facil_0034(p_pin) then raise exception 'pin_facil'; end if;
  v_hash := public.pin_de_0034(p_pin);
  if exists (select 1 from public.equipe_pins where hash = v_hash and membro_id <> p_membro and ativo) then raise exception 'pin_em_uso'; end if;
  update public.equipe_pins set hash = 'livre:' || membro_id || ':' || extract(epoch from clock_timestamp())::text
   where hash = v_hash and membro_id <> p_membro and not ativo;
  insert into public.equipe_pins (membro_id, hash, trocar, ativo, atualizado_em, por)
  values (p_membro, v_hash, false, true, now(), coalesce(public.ref_atual(), ''))
  on conflict (membro_id) do update set hash = excluded.hash, trocar = false, ativo = true, atualizado_em = now(), por = excluded.por;
  perform public.pin_tocar_membro_0034(p_membro);
  perform public.seguranca_registrar_0034('pin_definido', p_membro, v_nome, 'Senha de 4 números definida pela senha mestre.', '');
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.pin_definir(text, text) from public, anon;
grant execute on function public.pin_definir(text, text) to authenticated;

create or replace function public.pin_remover(p_membro text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  update public.equipe_pins set ativo = false, hash = 'removido:' || membro_id || ':' || extract(epoch from clock_timestamp())::text,
         atualizado_em = now(), por = coalesce(public.ref_atual(), '')
   where membro_id = p_membro;
  perform public.pin_tocar_membro_0034(p_membro);
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.pin_remover(text) from public, anon;
grant execute on function public.pin_remover(text) to authenticated;

-- Libera o acesso bloqueado por PIN errado (as tentativas erradas dele ficam marcadas como liberadas)
create or replace function public.pin_desbloquear(p_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  update public.pin_tentativas set liberado = true where ref = coalesce(p_ref, '') and not ok and not liberado;
  get diagnostics n = row_count;
  perform public.seguranca_registrar_0034('pin_liberado', coalesce(p_ref, ''), '', 'Assinatura com senha de 4 números liberada pela senha mestre.', '');
  return jsonb_build_object('ok', true, 'liberadas', n);
end $$;
revoke execute on function public.pin_desbloquear(text) from public, anon;
grant execute on function public.pin_desbloquear(text) to authenticated;

-- Acessos bloqueados agora para assinar (para a tela da senha mestre)
create or replace function public.pin_bloqueios()
returns table (ref text, nome text, erros int, ultimo timestamptz, ate_mestre boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  return query
    select t.ref, max(t.nome), count(*)::int, max(t.em), count(*) >= 10
      from public.pin_tentativas t
     where not t.ok and not t.liberado and t.em > now() - interval '24 hours'
     group by t.ref
    having count(*) >= 10 or count(*) filter (where t.em > now() - interval '15 minutes') >= 5;
end $$;
revoke execute on function public.pin_bloqueios() from public, anon;
grant execute on function public.pin_bloqueios() to authenticated;

-- Aprovação do pedido de senha feito pela própria pessoa: o PIN do pedido passa para a pessoa da equipe
create or replace function public.pin_aprovar_cadastro(p_pedido text, p_membro text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hash text;
  v_nome text;
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  select hash into v_hash from public.pin_pendentes where pedido_id = p_pedido and not usado;
  if v_hash is null then raise exception 'pedido'; end if;
  select data ->> 'nome' into v_nome from public.docs where colecao = 'equipe' and id = p_membro;
  if v_nome is null then raise exception 'membro'; end if;
  if exists (select 1 from public.equipe_pins where hash = v_hash and membro_id <> p_membro and ativo) then raise exception 'pin_em_uso'; end if;
  insert into public.equipe_pins (membro_id, hash, trocar, ativo, atualizado_em, por)
  values (p_membro, v_hash, false, true, now(), coalesce(public.ref_atual(), ''))
  on conflict (membro_id) do update set hash = excluded.hash, trocar = false, ativo = true, atualizado_em = now(), por = excluded.por;
  update public.pin_pendentes set usado = true where pedido_id = p_pedido;
  perform public.pin_tocar_membro_0034(p_membro);
  perform public.seguranca_registrar_0034('pin_definido', p_membro, v_nome, 'Senha de 4 números criada pela pessoa e aprovada pela senha mestre.', '');
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.pin_aprovar_cadastro(text, text) from public, anon;
grant execute on function public.pin_aprovar_cadastro(text, text) to authenticated;

-- Pedido recusado: o PIN do pedido é descartado
create or replace function public.pin_descartar_pedido(p_pedido text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.pin_e_mestre_0034() then raise exception 'permissao'; end if;
  update public.pin_pendentes set usado = true where pedido_id = p_pedido;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.pin_descartar_pedido(text) from public, anon;
grant execute on function public.pin_descartar_pedido(text) to authenticated;

-- Pedido de senha (0009) com o PIN guardado fora do documento. Aceita o PIN (app novo) ou o SHA-256 (app antigo).
create or replace function public.cadastro_pedir(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  papel text := coalesce(public.papel_atual(), '');
  v_cpf text := regexp_replace(coalesce(p ->> 'cpf', ''), '\D', '', 'g');
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_mat text := btrim(coalesce(p ->> 'matricula', ''));
  v_pin text := coalesce(p ->> 'pin', '');
  v_sha text := lower(coalesce(p ->> 'pinHash', ''));
  v_hash text;
  v_rh_id text; v_rh jsonb;
  v_id text;
  soma int; d1 int; d2 int; i int;
begin
  if papel not in ('mestre', 'equipe', 'setor') then raise exception 'sem_permissao'; end if;
  if length(v_nome) < 5 or position(' ' in v_nome) = 0 then raise exception 'nome'; end if;
  if length(v_cpf) <> 11 or v_cpf ~ '^(\d)\1{10}$' then raise exception 'cpf'; end if;
  soma := 0; for i in 1..9 loop soma := soma + substr(v_cpf, i, 1)::int * (11 - i); end loop;
  d1 := (soma * 10) % 11; if d1 = 10 then d1 := 0; end if;
  soma := 0; for i in 1..10 loop soma := soma + substr(v_cpf, i, 1)::int * (12 - i); end loop;
  d2 := (soma * 10) % 11; if d2 = 10 then d2 := 0; end if;
  if d1 <> substr(v_cpf, 10, 1)::int or d2 <> substr(v_cpf, 11, 1)::int then raise exception 'cpf'; end if;
  if v_pin <> '' then
    if v_pin !~ '^\d{4}$' then raise exception 'senha'; end if;
    if public.pin_facil_0034(v_pin) then raise exception 'pin_facil'; end if;
    v_hash := public.pin_de_0034(v_pin);
  elsif v_sha ~ '^[0-9a-f]{64}$' then
    v_hash := public.pin_hash_0034(v_sha);
  else
    raise exception 'senha';
  end if;
  if exists (select 1 from public.equipe_pins e join public.docs d on d.colecao = 'equipe' and d.id = e.membro_id
              where e.hash = v_hash and e.ativo and not e.trocar and public.sem_acento_0009(d.data ->> 'nome') <> public.sem_acento_0009(v_nome)) then
    raise exception 'senha_em_uso';
  end if;
  if exists (select 1 from public.docs where colecao = 'cadastro-pedidos' and data ->> 'status' = 'pendente' and data ->> 'cpf' = v_cpf) then raise exception 'ja_pedido'; end if;
  if coalesce(p ->> 'fotoDoc', '') !~ '^pedidos/' or coalesce(p ->> 'fotoRosto', '') !~ '^pedidos/' then raise exception 'fotos'; end if;
  if coalesce((p ->> 'aceite')::boolean, false) is not true then raise exception 'aceite'; end if;
  select m.id, m.dados into v_rh_id, v_rh from public.modulo_docs m
   where m.modulo = 'uniformes' and m.caminho = 'funcionarios'
     and ((v_mat <> '' and m.dados ->> 'matricula' = v_mat) or public.sem_acento_0009(m.dados ->> 'nome') = public.sem_acento_0009(v_nome))
   order by (v_mat <> '' and m.dados ->> 'matricula' = v_mat) desc limit 1;
  v_id := 'cp' || to_char(now(), 'YYYYMMDDHH24MISS') || substr(md5(random()::text), 1, 6);
  insert into public.pin_pendentes (pedido_id, hash) values (v_id, v_hash);
  insert into public.docs (colecao, id, data) values ('cadastro-pedidos', v_id, jsonb_build_object(
    'status', 'pendente', 'nome', v_nome, 'matricula', v_mat, 'cpf', v_cpf, 'temPin', true,
    'fotoDoc', p ->> 'fotoDoc', 'fotoRosto', p ->> 'fotoRosto', 'aceite', true, 'aceiteTexto', left(coalesce(p ->> 'aceiteTexto', ''), 400),
    'rh', case when v_rh_id is null then null else jsonb_build_object('id', v_rh_id, 'nome', v_rh ->> 'nome', 'matricula', v_rh ->> 'matricula',
      'funcao', v_rh ->> 'funcao', 'setor', v_rh ->> 'setor', 'admissao', v_rh ->> 'admissao') end,
    'pedidoPor', papel, 'criadoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  return jsonb_build_object('ok', true, 'id', v_id, 'rh', v_rh_id is not null);
end $$;
revoke execute on function public.cadastro_pedir(jsonb) from public, anon;
grant execute on function public.cadastro_pedir(jsonb) to authenticated;

-- PINs que já existiam: passam para equipe_pins (sem ninguém digitar de novo)
insert into public.equipe_pins (membro_id, hash, trocar, por)
select d.id, public.pin_hash_0034(lower(d.data ->> 'pinHash')), false, 'migração 0034'
  from public.docs d
 where d.colecao = 'equipe' and coalesce(d.data ->> 'pinHash', '') ~ '^[0-9a-fA-F]{64}$'
on conflict (membro_id) do nothing;
insert into public.pin_pendentes (pedido_id, hash)
select d.id, public.pin_hash_0034(lower(d.data ->> 'pinHash'))
  from public.docs d
 where d.colecao = 'cadastro-pedidos' and d.data ->> 'status' = 'pendente' and coalesce(d.data ->> 'pinHash', '') ~ '^[0-9a-fA-F]{64}$'
on conflict (pedido_id) do nothing;
-- Os PINs que estavam escritos no código público do app foram marcados "trocar" à parte (dado, não regra).
