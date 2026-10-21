-- LEVÍSSIMA · 0028 (pedidos de 21/10/2026)
--
-- * Minha agenda: quem foi chamado para um compromisso ACEITA ou NÃO ACEITA (respostas = { ref: 'aceito' | 'recusado' }).
--   Se o dono muda o dia ou a hora, as respostas zeram (todos respondem de novo). Só pela função compromisso_responder.
-- * Aniversariante do dia para todos: aniversariantes_hoje() devolve só o nome e o setor (área) de quem faz aniversário
--   hoje (horário de Brasília), para qualquer acesso — sem o resto do cadastro da equipe.
-- * Brindes e presentes: coleção "brindes" só para a senha mestre e para quem tiver "Vê a aba Brindes e presentes"
--   marcado em Cadastros › Equipe (veBrindes); acessos da diretoria também precisam da marca.

alter table public.compromissos add column if not exists respostas jsonb not null default '{}'::jsonb;

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
           saiu = array(select unnest(antes.saiu) intersect select unnest(v_part)),
           -- mudou dia ou hora: todos respondem de novo; senão, ficam as respostas de quem continua incluído
           respostas = case when antes.data is distinct from v_data or antes.inicio is distinct from v_ini or antes.fim is distinct from v_fim
                            then '{}'::jsonb
                            else (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(antes.respostas) e where e.key = any (v_part)) end
     where c.id = p_id returning * into r;
  end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.compromisso_salvar(bigint, jsonb) from public, anon;
grant execute on function public.compromisso_salvar(bigint, jsonb) to authenticated;

-- quem foi chamado aceita ('aceito') ou não aceita ('recusado'); nulo tira a resposta
create or replace function public.compromisso_responder(p_id bigint, p_resposta text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_eu text := public.ref_atual(); v_r text := nullif(btrim(coalesce(p_resposta, '')), ''); r public.compromissos;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_r is not null and v_r not in ('aceito', 'recusado') then raise exception 'resposta' using errcode = '22023'; end if;
  update public.compromissos c
     set respostas = case when v_r is null then c.respostas - v_eu else c.respostas || jsonb_build_object(v_eu, v_r) end,
         vistos = array(select distinct unnest(c.vistos || v_eu)), atualizado_em = now()
   where c.id = p_id and v_eu = any (c.participantes) and not (v_eu = any (c.saiu)) and not c.cancelado
  returning * into r;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  return to_jsonb(r);
end $$;
revoke execute on function public.compromisso_responder(bigint, text) from public, anon;
grant execute on function public.compromisso_responder(bigint, text) to authenticated;

-- aniversariantes de hoje: só nome e setor (área), para qualquer acesso
create or replace function public.aniversariantes_hoje()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with h as (select (now() at time zone 'America/Sao_Paulo')::date as d)
  select coalesce(jsonb_agg(jsonb_build_object('nome', e.data ->> 'nome', 'setor', coalesce(e.data ->> 'area', '')) order by e.data ->> 'nome'), '[]'::jsonb)
    from public.docs e, h
   where e.colecao = 'equipe' and coalesce(e.data ->> 'aniversario', '') <> '' and e.data ->> 'ativo' is distinct from 'false'
     and (e.data ->> 'aniversario' = to_char(h.d, 'MM-DD')
          or (e.data ->> 'aniversario' = '02-29' and to_char(h.d, 'MM-DD') = '02-28'
              and extract(day from (date_trunc('year', h.d) + interval '2 month' - interval '1 day')) = 28));
$$;
revoke execute on function public.aniversariantes_hoje() from public, anon;
grant execute on function public.aniversariantes_hoje() to authenticated;

-- brindes e presentes: senha mestre e quem tiver a marca veBrindes na equipe
create or replace function public.brindes_pode_0028()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); m jsonb;
begin
  if r = 'mestre' then return true; end if;
  if r like 'escritorio:%' then
    select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  elsif r like 'diretoria:%' then
    select data into m from public.docs where colecao = 'equipe' and public.sem_acento_0009(data ->> 'nome') = public.sem_acento_0009(public.nome_atual()) limit 1;
  end if;
  return coalesce(m -> 'veBrindes' = 'true'::jsonb, false);
end $$;
revoke execute on function public.brindes_pode_0028() from public, anon;
grant execute on function public.brindes_pode_0028() to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'brindes_0028') then
    create policy "brindes_0028" on public.docs as restrictive for all to authenticated
      using (colecao <> 'brindes' or public.brindes_pode_0028())
      with check (colecao <> 'brindes' or public.brindes_pode_0028());
  end if;
end $$;
