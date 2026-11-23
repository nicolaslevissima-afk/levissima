-- LEVÍSSIMA · teste da 0062 (turnos do RH). Ver como rodar em testes/turnos-banco.sql.
\set ON_ERROR_STOP 1

-- 1) cadastro inicial e linhas ligadas ao RH, com a cópia do horário
do $t$
declare v jsonb;
begin
  select data -> 'turnos' into v from public.docs where colecao = 'mp-config' and id = 'turnos';
  assert jsonb_array_length(v) = 6, 'o cadastro começa com 6 turnos';
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'l1';
  assert v -> 0 ->> 'rhId' = 'desc1' and v -> 0 ->> 'nome' = 'DESC 1', 'Linha 1: DESC 1 ligado ao RH sem mudar o nome: ' || v::text;
  assert jsonb_array_length(v -> 0 -> 'faixas') = 2 and v -> 0 ->> 'inicio' = '03:06' and v -> 0 -> 'dias' = '[1,2,3,4,5,6]'::jsonb and (v -> 0 ->> 'pausa')::int = 0, 'DESC 1 com as duas faixas do RH: ' || (v -> 0)::text;
  assert v -> 2 ->> 'rhId' = 'desc3' and v -> 2 -> 'faixas' -> 1 ->> 'inicio' = '18:42' and v -> 2 -> 'dias' = '[1,2,3,4,5]'::jsonb, 'DESC 3: sexta às 18:42';
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'g10';
  assert jsonb_array_length(v) = 2 and v -> 0 ->> 'rhId' = 'galao-dia' and v -> 0 ->> 'inicio' = '05:00' and v -> 0 ->> 'fim' = '15:00' and v -> 1 ->> 'inicio' = '11:00' and v -> 1 ->> 'fim' = '21:00'
         and v -> 0 -> 'dias' = '[1,2,3,4,5]'::jsonb, 'Linha 10 L com Galão dia e noite: ' || v::text;
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'retornavel';
  assert v -> 0 ->> 'nome' = 'Retornável 1 (dia)' and v -> 0 ->> 'rhId' = 'galao-dia' and v -> 1 ->> 'rhId' = 'galao-noite' and v -> 1 ->> 'inicio' = '11:00', 'Retornável dia e noite ligados: ' || v::text;
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'copo';
  assert jsonb_array_length(v) = 0, 'Copos continua sem turno';
  raise notice 'ok 1: cadastro inicial e linhas ligadas';
end $t$;

-- 2) quem tem a aba RH em "Edita" muda o turno e as linhas acompanham
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"app_metadata":{"papel":"equipe","ref":"escritorio:equipe-andre","modulos":["abas","aba:rh","aba:pcp"]}}', true);
update public.docs set data = jsonb_set(data, '{turnos,3,faixas,0,entrada}', '"06:00"') where colecao = 'mp-config' and id = 'turnos';
do $t$
declare v jsonb;
begin
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'g10';
  assert v -> 0 ->> 'inicio' = '06:00', 'Linha 10 L acompanhou o RH: ' || v::text;
  raise notice 'ok 2: RH em Edita grava e as linhas acompanham';
end $t$;
commit;

-- 3) só visualiza no RH (e o PCP sem a aba RH) não grava
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"app_metadata":{"papel":"equipe","ref":"escritorio:equipe-laura","modulos":["abas","aba:rh","ver:rh","aba:pcp"]}}', true);
do $t$
declare n int;
begin
  update public.docs set data = jsonb_set(data, '{turnos,3,faixas,0,entrada}', '"07:00"') where colecao = 'mp-config' and id = 'turnos';
  get diagnostics n = row_count;
  assert n = 0, 'só visualiza não altera';
  raise notice 'ok 3: só visualiza não grava';
end $t$;
commit;

-- 4) tirar um turno usado por uma linha: recusa; horário errado: recusa
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"app_metadata":{"papel":"equipe","ref":"escritorio:equipe-andre","modulos":["abas","aba:rh"]}}', true);
do $t$
begin
  begin
    update public.docs set data = jsonb_set(data, '{turnos}', (data -> 'turnos') - 3) where colecao = 'mp-config' and id = 'turnos';
    raise exception 'devia recusar';
  exception when others then
    assert sqlerrm like '%usado por uma linha%', 'mensagem: ' || sqlerrm;
  end;
  begin
    update public.docs set data = jsonb_set(data, '{turnos,0,faixas,0,saida}', '"25:00"') where colecao = 'mp-config' and id = 'turnos';
    raise exception 'devia recusar';
  exception when others then
    assert sqlerrm like '%entrada e a saída%', 'mensagem: ' || sqlerrm;
  end;
  begin
    update public.docs set data = jsonb_set(data, '{turnos,0,faixas,0,dias}', '[]') where colecao = 'mp-config' and id = 'turnos';
    raise exception 'devia recusar';
  exception when others then
    assert sqlerrm like '%marque os dias%', 'mensagem: ' || sqlerrm;
  end;
  -- incluir um turno novo e tirar um que nenhuma linha usa: pode
  update public.docs set data = jsonb_set(data, '{turnos}', (data -> 'turnos') || '[{"id":"extra-sab","nome":"Extra de sábado","faixas":[{"dias":[6],"entrada":"07:00","saida":"11:00"}]}]') where colecao = 'mp-config' and id = 'turnos';
  update public.docs set data = jsonb_set(data, '{turnos}', (data -> 'turnos') - 5) where colecao = 'mp-config' and id = 'turnos'; -- adm
  assert (select jsonb_array_length(data -> 'turnos') from public.docs where colecao = 'mp-config' and id = 'turnos') = 6, 'incluiu um e tirou o Administrativo';
  raise notice 'ok 4: guarda do cadastro';
end $t$;
commit;

-- 5) "Configura o PCP" salva a linha ligando um turno do RH: a cópia do horário vem do banco
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"app_metadata":{"papel":"equipe","ref":"escritorio:equipe-laura","modulos":["abas","aba:pcp"]}}', true);
update public.docs d set data = jsonb_set(d.data, '{linhas}', (
  select jsonb_agg(case when l ->> 'id' = 'copo' then jsonb_set(l, '{turnos}', '[{"nome":"Extra de sábado","rhId":"extra-sab"}]') else l end order by o)
    from jsonb_array_elements(d.data -> 'linhas') with ordinality x(l, o)))
 where colecao = 'mp-config' and id = 'linhas-producao';
do $t$
declare v jsonb;
begin
  select l -> 'turnos' into v from public.docs d, jsonb_array_elements(d.data -> 'linhas') l where d.colecao = 'mp-config' and d.id = 'linhas-producao' and l ->> 'id' = 'copo';
  assert v -> 0 ->> 'inicio' = '07:00' and v -> 0 ->> 'fim' = '11:00' and v -> 0 -> 'dias' = '[6]'::jsonb, 'Copos com o turno do RH: ' || v::text;
  raise notice 'ok 5: a linha salva recebe o horário do RH';
end $t$;
commit;
select 'turnos-sql: tudo certo' as resultado;
