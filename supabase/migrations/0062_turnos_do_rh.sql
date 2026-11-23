-- LEVÍSSIMA · 0062: turnos da produção vêm do cadastro do RH (pedido de 23/11/2026).
-- * O RH vira o cadastro dos turnos: mp-config/turnos = { turnos: [{ id, nome, faixas: [{ dias, entrada, saida,
--   refeicaoDe, refeicaoAte }] }] }. Grava: a senha mestre e quem tem a aba RH em "Edita" (grava_aba_marcada_0042).
--   Lê: o escritório (as mesmas regras de mp-config).
-- * As linhas do PCP escolhem os turnos do RH (turno da linha com "rhId"); o horário vem do RH. Para o tablet da
--   máquina (que lê só a configuração das linhas), o turno ligado recebe uma cópia do horário (faixas, inicio, fim,
--   dias), refeita aqui no banco quando a linha é salva e quando o RH muda um turno. A refeição não para a linha
--   (pausa 0 no PCP).
-- * Um turno do RH que alguma linha usa não pode ser tirado (primeiro tire da linha).
-- * Dados: o cadastro começa com os turnos que o RH já usava (Desc 1, 2 e 3 com os horários de cada dia, Galão dia
--   05:00–15:00 e Galão noite 11:00–21:00 de segunda a sexta, Administrativo sem horário) e as linhas passam a
--   puxar do RH: DESC 1, 2 e 3 (Linha 1, Linha 2 e Linha 6 L), Retornável (dia e noite) e Linha 10 L (Galão dia e
--   noite).

-- faixas do RH no formato do PCP: [{ inicio, fim, dias }] (só as que têm horário e dias)
create or replace function public.turnos_rh_faixas_0062(t jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object('inicio', f ->> 'entrada', 'fim', f ->> 'saida', 'dias', f -> 'dias') order by o), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(t -> 'faixas') = 'array' then t -> 'faixas' else '[]'::jsonb end) with ordinality x(f, o)
   where coalesce(f ->> 'entrada', '') ~ '^\d{2}:\d{2}$' and coalesce(f ->> 'saida', '') ~ '^\d{2}:\d{2}$'
     and f ->> 'entrada' <> f ->> 'saida' and jsonb_typeof(f -> 'dias') = 'array' and jsonb_array_length(f -> 'dias') > 0;
$$;
revoke execute on function public.turnos_rh_faixas_0062(jsonb) from public, anon;

-- os turnos das linhas ligados ao RH (rhId) recebem a cópia do horário do RH
create or replace function public.turnos_rh_resolver_0062(p_linhas jsonb, p_reg jsonb)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  saida jsonb := '[]'::jsonb; l jsonb; t jsonb; ts jsonb; r jsonb; fx jsonb; ds jsonb;
begin
  if jsonb_typeof(p_linhas) <> 'array' then return p_linhas; end if;
  for l in select x from jsonb_array_elements(p_linhas) x loop
    if jsonb_typeof(l -> 'turnos') = 'array' then
      ts := '[]'::jsonb;
      for t in select y from jsonb_array_elements(l -> 'turnos') y loop
        if jsonb_typeof(t) = 'object' and coalesce(t ->> 'rhId', '') <> '' then
          select z into r from jsonb_array_elements(case when jsonb_typeof(p_reg -> 'turnos') = 'array' then p_reg -> 'turnos' else '[]'::jsonb end) z
           where z ->> 'id' = t ->> 'rhId' limit 1;
          if r is not null then
            fx := public.turnos_rh_faixas_0062(r);
            t := (t - 'inicio' - 'fim' - 'dias' - 'faixas' - 'pausa' - 'pausas') || jsonb_build_object('pausa', 0);
            if jsonb_array_length(fx) > 0 then
              select coalesce(jsonb_agg(distinct d order by d), '[]'::jsonb) into ds
                from jsonb_array_elements(fx) f, jsonb_array_elements(f -> 'dias') d;
              t := t || jsonb_build_object('faixas', fx, 'inicio', fx -> 0 ->> 'inicio', 'fim', fx -> 0 ->> 'fim', 'dias', ds);
            end if;
          end if;
        end if;
        ts := ts || jsonb_build_array(t);
      end loop;
      l := jsonb_set(l, '{turnos}', ts);
    end if;
    saida := saida || jsonb_build_array(l);
  end loop;
  return saida;
end $$;
revoke execute on function public.turnos_rh_resolver_0062(jsonb, jsonb) from public, anon;

-- ao salvar a configuração das linhas: refaz a cópia do horário dos turnos ligados ao RH
create or replace function public.linhas_turnos_rh_0062()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare reg jsonb;
begin
  select data into reg from public.docs where colecao = 'mp-config' and id = 'turnos';
  if reg is not null and jsonb_typeof(new.data -> 'linhas') = 'array' then
    new.data := jsonb_set(new.data, '{linhas}', public.turnos_rh_resolver_0062(new.data -> 'linhas', reg));
  end if;
  return new;
end $$;
revoke execute on function public.linhas_turnos_rh_0062() from public, anon, authenticated;

-- o cadastro dos turnos: formato, horários e "não tirar o turno que uma linha usa"
create or replace function public.turnos_rh_guarda_0062()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t jsonb; f jsonb; ids text[] := '{}'; usados text[];
begin
  -- gravar por cima de um que já existe vira atualização (o gatilho de atualização confere)
  if tg_op = 'INSERT' and exists (select 1 from public.docs where colecao = new.colecao and id = new.id) then return new; end if;
  if jsonb_typeof(new.data -> 'turnos') <> 'array' then raise exception 'turnos: lista inválida'; end if;
  if jsonb_array_length(new.data -> 'turnos') > 60 then raise exception 'turnos: no máximo 60'; end if;
  for t in select x from jsonb_array_elements(new.data -> 'turnos') x loop
    if jsonb_typeof(t) <> 'object' or coalesce(t ->> 'id', '') !~ '^[a-z0-9][a-z0-9-]{0,39}$' then raise exception 'turnos: identificação inválida'; end if;
    if t ->> 'id' in ('especial', '') then raise exception 'turnos: "%" é reservado', t ->> 'id'; end if;
    if t ->> 'id' = any(ids) then raise exception 'turnos: o turno % está duas vezes', t ->> 'id'; end if;
    ids := ids || (t ->> 'id');
    if length(btrim(coalesce(t ->> 'nome', ''))) = 0 or length(t ->> 'nome') > 60 then raise exception 'turnos: dê um nome a cada turno'; end if;
    if t ? 'faixas' and jsonb_typeof(t -> 'faixas') <> 'array' then raise exception 'turnos: horários inválidos (%)', t ->> 'nome'; end if;
    for f in select y from jsonb_array_elements(coalesce(t -> 'faixas', '[]'::jsonb)) y loop
      if coalesce(f ->> 'entrada', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(f ->> 'saida', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' or f ->> 'entrada' = f ->> 'saida' then
        raise exception 'turnos: confira a entrada e a saída (%)', t ->> 'nome';
      end if;
      if jsonb_typeof(f -> 'dias') <> 'array' or jsonb_array_length(f -> 'dias') = 0
         or exists (select 1 from jsonb_array_elements(f -> 'dias') d where case when jsonb_typeof(d) = 'number' then (d::text)::numeric not in (0, 1, 2, 3, 4, 5, 6) else true end) then
        raise exception 'turnos: marque os dias (%)', t ->> 'nome';
      end if;
      if coalesce(f ->> 'refeicaoDe', '') <> '' and coalesce(f ->> 'refeicaoDe', '') !~ '^([01]\d|2[0-3]):[0-5]\d$'
         or coalesce(f ->> 'refeicaoAte', '') <> '' and coalesce(f ->> 'refeicaoAte', '') !~ '^([01]\d|2[0-3]):[0-5]\d$' then
        raise exception 'turnos: confira a refeição (%)', t ->> 'nome';
      end if;
    end loop;
  end loop;
  select coalesce(array_agg(distinct tt ->> 'rhId'), '{}') into usados
    from public.docs d, jsonb_array_elements(coalesce(d.data -> 'linhas', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'turnos', '[]'::jsonb)) tt
   where d.colecao = 'mp-config' and d.id = 'linhas-producao' and jsonb_typeof(tt) = 'object' and coalesce(tt ->> 'rhId', '') <> '';
  if exists (select 1 from unnest(usados) u where u <> all(ids)) then
    raise exception 'turnos: o turno % é usado por uma linha do PCP; tire da linha primeiro', (select u from unnest(usados) u where u <> all(ids) limit 1);
  end if;
  return new;
end $$;
revoke execute on function public.turnos_rh_guarda_0062() from public, anon, authenticated;

-- o RH mudou os turnos: as linhas refazem a cópia do horário (o gatilho das linhas faz a conta)
create or replace function public.turnos_rh_sincroniza_0062()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.docs set data = data, atualizado_em = now() where colecao = 'mp-config' and id = 'linhas-producao';
  return null;
end $$;
revoke execute on function public.turnos_rh_sincroniza_0062() from public, anon, authenticated;

drop trigger if exists linhas_turnos_rh_0062 on public.docs;
create trigger linhas_turnos_rh_0062 before insert or update on public.docs
  for each row when (new.colecao = 'mp-config' and new.id = 'linhas-producao') execute function public.linhas_turnos_rh_0062();
drop trigger if exists turnos_rh_guarda_0062 on public.docs;
create trigger turnos_rh_guarda_0062 before insert or update on public.docs
  for each row when (new.colecao = 'mp-config' and new.id = 'turnos') execute function public.turnos_rh_guarda_0062();
drop trigger if exists turnos_rh_sincroniza_0062 on public.docs;
create trigger turnos_rh_sincroniza_0062 after insert or update on public.docs
  for each row when (new.colecao = 'mp-config' and new.id = 'turnos') execute function public.turnos_rh_sincroniza_0062();

-- quem grava o cadastro dos turnos: senha mestre e a aba RH em "Edita" (apagar continua só da senha mestre)
alter policy "producao_cadastro_grava" on public.docs
  with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
              or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052()))
              or (colecao = 'mp-config' and id = 'turnos' and (select public.grava_aba_marcada_0042('rh'))));
alter policy "producao_cadastro_altera" on public.docs
  using (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
         or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052()))
         or (colecao = 'mp-config' and id = 'turnos' and (select public.grava_aba_marcada_0042('rh'))))
  with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
              or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052()))
              or (colecao = 'mp-config' and id = 'turnos' and (select public.grava_aba_marcada_0042('rh'))));

-- o cadastro começa com os turnos que o RH já usava (não muda nada se já existir)
insert into public.docs (colecao, id, data)
values ('mp-config', 'turnos', jsonb_build_object('turnos', '[
  {"id": "desc1", "nome": "Desc 1 (6x1)", "faixas": [
    {"dias": [1], "entrada": "03:06", "saida": "13:15", "refeicaoDe": "07:00", "refeicaoAte": "08:00"},
    {"dias": [2, 3, 4, 5, 6], "entrada": "05:20", "saida": "13:15", "refeicaoDe": "10:00", "refeicaoAte": "11:00"}]},
  {"id": "desc2", "nome": "Desc 2 (6x1)", "faixas": [
    {"dias": [1, 2, 3, 4, 5], "entrada": "12:10", "saida": "21:00", "refeicaoDe": "18:00", "refeicaoAte": "19:00"},
    {"dias": [6], "entrada": "13:10", "saida": "18:00"}]},
  {"id": "desc3", "nome": "Desc 3 (5x2)", "faixas": [
    {"dias": [1, 2, 3, 4], "entrada": "20:55", "saida": "05:20", "refeicaoDe": "01:00", "refeicaoAte": "02:00"},
    {"dias": [5], "entrada": "18:42", "saida": "05:20", "refeicaoDe": "01:00", "refeicaoAte": "02:00"}]},
  {"id": "galao-dia", "nome": "Galão · turno dia", "faixas": [{"dias": [1, 2, 3, 4, 5], "entrada": "05:00", "saida": "15:00"}]},
  {"id": "galao-noite", "nome": "Galão · turno noite", "faixas": [{"dias": [1, 2, 3, 4, 5], "entrada": "11:00", "saida": "21:00"}]},
  {"id": "adm", "nome": "Administrativo", "faixas": []}
]'::jsonb, 'criadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), 'criadoPor', 'migração 0062'))
on conflict (colecao, id) do nothing;

-- as linhas passam a puxar o horário do RH (só os turnos ainda sem rhId; o nome do turno na linha fica igual)
do $$
declare
  d jsonb; ls jsonb := '[]'::jsonb; l jsonb; ts jsonb; t jsonb; nome text; rid text;
begin
  select data into d from public.docs where colecao = 'mp-config' and id = 'linhas-producao';
  if d is null or jsonb_typeof(d -> 'linhas') <> 'array' then return; end if;
  for l in select x from jsonb_array_elements(d -> 'linhas') x loop
    ts := '[]'::jsonb;
    for t in select y from jsonb_array_elements(case when jsonb_typeof(l -> 'turnos') = 'array' then l -> 'turnos' else '[]'::jsonb end) y loop
      nome := case when jsonb_typeof(t) = 'string' then t #>> '{}' else coalesce(t ->> 'nome', '') end;
      if jsonb_typeof(t) = 'string' then t := jsonb_build_object('nome', nome); end if;
      rid := coalesce(t ->> 'rhId', '');
      if rid = '' then
        rid := case
          when upper(regexp_replace(nome, '\s+', ' ', 'g')) = 'DESC 1' then 'desc1'
          when upper(regexp_replace(nome, '\s+', ' ', 'g')) = 'DESC 2' then 'desc2'
          when upper(regexp_replace(nome, '\s+', ' ', 'g')) = 'DESC 3' then 'desc3'
          when l ->> 'id' = 'retornavel' and nome ilike '%dia%' then 'galao-dia'
          when l ->> 'id' = 'retornavel' and nome ilike '%noite%' then 'galao-noite'
          else '' end;
        if rid <> '' then t := t || jsonb_build_object('rhId', rid); end if;
      end if;
      ts := ts || jsonb_build_array(t);
    end loop;
    if l ->> 'id' = 'g10' and jsonb_array_length(ts) = 0 then
      ts := '[{"nome": "Galão · turno dia", "rhId": "galao-dia"}, {"nome": "Galão · turno noite", "rhId": "galao-noite"}]'::jsonb;
    end if;
    ls := ls || jsonb_build_array(jsonb_set(l, '{turnos}', ts));
  end loop;
  update public.docs set data = jsonb_set(data, '{linhas}', ls), atualizado_em = now() where colecao = 'mp-config' and id = 'linhas-producao';
end $$;
