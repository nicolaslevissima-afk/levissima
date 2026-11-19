-- LEVÍSSIMA · testes das regras do Garrafões no banco (0056 + 0057): perfis, gravação direta bloqueada, lote por
-- fabricação, marcas por modelo, sucata por litragem, venda e troca com assinatura, entrada com foto da nota,
-- retirada, recebimento vinculado, contagem, exclusão com recálculo, idempotência e origem.
-- Rodar: createdb t && psql -d t -f testes/garrafoes-banco.sql -f supabase/migrations/0056_garrafoes_estoque.sql
--        -f supabase/migrations/0057_garrafoes_fabricacao_assinatura.sql -f testes/garrafoes-sql.sql
-- Termina com 'TODOS OS TESTES PASSARAM'.
\set ON_ERROR_STOP on
create schema teste;
grant usage on schema teste to authenticated;
create function teste.como(p_ref text) returns void language plpgsql security definer as $$
declare a record;
begin
  if p_ref = 'mestre' then
    perform set_config('request.jwt.claims', '{"app_metadata":{"papel":"mestre","ref":"mestre","nome":"Mestre"}}', false); return;
  end if;
  select * into a from public.acesso_senhas where ref = p_ref;
  perform set_config('request.jwt.claims', jsonb_build_object('app_metadata', jsonb_build_object('papel', a.papel, 'ref', a.ref, 'nome', a.nome, 'modulos', to_jsonb(a.modulos)))::text, false);
end $$;
create function teste.erro(p_sql text, p_trecho text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_trecho in sqlerrm) = 0 then raise exception 'FALHOU: esperava "%", veio "%" em %', p_trecho, sqlerrm, p_sql; end if;
    raise notice 'ok (recusou): %', sqlerrm;
    return;
  end;
  raise exception 'FALHOU: deveria recusar (%): %', p_trecho, p_sql;
end $$;
create function teste.saldo(p_modelo text, p_chave text) returns bigint language sql security definer as $$
  select coalesce((public.garrafoes_saldos_0057(p_modelo) ->> p_chave)::bigint, 0) $$;
create function teste.conta(p_caminho text, p_id text) returns int language sql security definer as $$
  select count(*)::int from public.modulo_docs where modulo = 'garrafoes' and caminho = p_caminho and (p_id is null or id = p_id) $$;
create function teste.png() returns text language sql as $$ select 'data:image/png;base64,' || repeat('iVBORw0KGgo', 300) $$;
create function teste.jpg() returns text language sql as $$ select 'data:image/jpeg;base64,' || repeat('/9j/4AAQSkZJRg', 800) $$;
create function teste.ass(p_resumo text) returns jsonb language sql as $$ select jsonb_build_object('imagem', teste.png(), 'resumo', p_resumo) $$;
grant execute on all functions in schema teste to authenticated;

set role authenticated;
do $$
declare r jsonb; hoje text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  ontem text := to_char((now() at time zone 'America/Sao_Paulo')::date - 1, 'YYYY-MM-DD');
  fab1 text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM');
  fab0 text := to_char((now() at time zone 'America/Sao_Paulo')::date - 40, 'YYYY-MM');
  futuro text := to_char((now() at time zone 'America/Sao_Paulo')::date + 62, 'YYYY-MM'); n int;
begin
  -- perfis (0056)
  perform teste.como('escritorio:gestora'); if public.garrafoes_eu() ->> 'perfil' <> 'gestao' then raise exception 'gestora'; end if;
  perform teste.como('escritorio:conta'); if public.garrafoes_eu() ->> 'perfil' <> 'consulta' then raise exception 'conta deveria ser consulta'; end if;
  perform teste.erro($q$select public.garrafoes_registrar('{"id":"op-AAAAAAAAAAAA1","tipo":"entrada","modelo":"20L","data":"2026-11-10","linhas":[{"marca":"AGS","fabricacao":"2026-10","qtd":10}]}')$q$, 'Seu perfil não registra entradas');
  perform teste.erro($q$insert into public.modulo_docs (modulo,caminho,id,dados) values ('garrafoes','g-assin','op-xxxxxxxxxxxxxx','{}')$q$, 'row-level security');
  perform teste.erro($q$insert into public.modulo_docs (modulo,caminho,id,dados) values ('garrafoes','g-fotos','op-xxxxxxxxxxxxxx','{}')$q$, 'row-level security');
  perform teste.como('escritorio:gestora');
  perform public.garrafoes_perfil_definir('escritorio:conta', 'entradas');
  perform public.garrafoes_perfil_definir('escritorio:entrega', 'entregas');

  -- ENTRADA: foto obrigatória; lote = marca + fabricação; mesma combinação soma
  perform teste.como('escritorio:conta');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000001","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"Montico","fabricacao":"%s","qtd":50}]}')$q$, hoje, fab1), 'Falta a foto da nota');
  if teste.conta('g-ops', null) <> 0 then raise exception 'entrada sem foto gravou'; end if;
  r := public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000001','tipo','entrada','modelo','20L','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao',fab1,'qtd',50))));
  if teste.saldo('20L','N|Montico|' || fab1) <> 50 or teste.conta('g-fotos','op-ENTRADA000001') <> 1 or not (r ? 'fotoNota') then raise exception 'entrada com foto: %', r; end if;
  if r ? 'obs' then raise exception 'entrada não tem observação'; end if;
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000002','tipo','entrada','modelo','20L','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao',fab1,'qtd',20))));
  if teste.saldo('20L','N|Montico|' || fab1) <> 70 then raise exception 'mesma fabricação deveria somar'; end if;
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000003','tipo','entrada','modelo','20L','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao',fab0,'qtd',30))));
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000004','tipo','entrada','modelo','20L','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao',fab1,'qtd',40))));
  if teste.saldo('20L','N|Montico|' || fab0) <> 30 or teste.saldo('20L','N|AGS|' || fab1) <> 40 then raise exception 'fabricações e marcas separadas'; end if;
  -- marcas por modelo e fabricação válida
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000005','tipo','entrada','modelo','20LR','data','%s','foto',teste.jpg(),'linhas',jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao','%s','qtd',5))))$q$, hoje, fab1), 'Montico ou Angioplast');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000005','tipo','entrada','modelo','20L','data','%s','foto',teste.jpg(),'linhas',jsonb_build_array(jsonb_build_object('marca','Angioplast','fabricacao','%s','qtd',5))))$q$, hoje, fab1), 'AGS ou Montico');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000005','tipo','entrada','modelo','20L','data','%s','foto',teste.jpg(),'linhas',jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao','%s','qtd',5))))$q$, hoje, futuro), 'não pode ser depois da data');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000005','tipo','entrada','modelo','20L','data','%s','foto','data:image/png;base64,AAAA','linhas',jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao','%s','qtd',5))))$q$, hoje, fab1), 'Falta a foto da nota');
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000006','tipo','entrada','modelo','20LR','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Angioplast','fabricacao',fab0,'qtd',24))));
  if teste.saldo('20LR','N|Angioplast|' || fab0) <> 24 then raise exception '20LR Angioplast'; end if;
  -- clique duplo
  r := public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000006','tipo','entrada','modelo','20LR','data',hoje,'foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Angioplast','fabricacao',fab0,'qtd',24))));
  if not (r ? 'repetida') or teste.saldo('20LR','N|Angioplast|' || fab0) <> 24 then raise exception 'duplicou'; end if;

  -- VENDA: cliente e assinatura antes da baixa; uma marca; várias fabricações
  perform teste.como('escritorio:entrega');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data','%s','cliente','Mercado X','linhas',jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao','%s','qtd',10))))$q$, hoje, fab1), 'Falta a assinatura do cliente');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data','%s','assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao','%s','qtd',10))))$q$, hoje, fab1), 'Informe o cliente');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data','%s','cliente','Mercado X','assinatura',jsonb_build_object('imagem',teste.png()),'linhas',jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao','%s','qtd',10))))$q$, hoje, fab1), 'Falta o resumo');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data','%s','cliente','Mercado X','assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao','%s','qtd',10),jsonb_build_object('marca','AGS','fabricacao','%s','qtd',1))))$q$, hoje, fab1, fab1), 'uma marca por vez');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data','%s','cliente','Mercado X','assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao','%s','qtd',31))))$q$, hoje, fab0), 'têm 30 unidade(s)');
  if teste.conta('g-ops', 'op-VENDA00000001') <> 0 or teste.conta('g-assin', null) <> 0 then raise exception 'venda recusada gravou algo'; end if;
  r := public.garrafoes_registrar(jsonb_build_object('id','op-VENDA00000001','tipo','saida','modelo','20L','data',hoje,'cliente','Mercado X',
        'assinatura', teste.ass('Entrega: 10 Montico fab. ' || fab1 || '; 5 Montico fab. ' || fab0),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao',fab1,'qtd',10), jsonb_build_object('marca','Montico','fabricacao',fab0,'qtd',5))));
  if teste.saldo('20L','N|Montico|' || fab1) <> 60 or teste.saldo('20L','N|Montico|' || fab0) <> 25 or teste.saldo('20L','N|AGS|' || fab1) <> 40 then raise exception 'venda baixa nas fabricações'; end if;
  select count(*) into n from public.modulo_docs where modulo='garrafoes' and caminho='g-assin' and id='op-VENDA00000001' and dados->>'cliente' = 'Mercado X' and dados->>'resumo' like 'Entrega: 10 Montico%' and dados->'por'->>'nome' = 'Entregador';
  if n <> 1 or not (r ? 'assinada') then raise exception 'assinatura guardada com resumo, cliente e responsável'; end if;

  -- TROCA (exemplo do pedido): 15 sucatas de 20 L por 3 novos Montico fab1; AGS não muda
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-TROCA00000001','tipo','troca','modelo','20L','data','%s','cliente','Cliente Y','totalSucata',15,'linhas',jsonb_build_array(jsonb_build_object('classe','sucata','motivo','Vencido','qtd',15),jsonb_build_object('classe','novo','marca','Montico','fabricacao','%s','qtd',3))))$q$, hoje, fab1), 'Falta a assinatura do cliente');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-TROCA00000001','tipo','troca','modelo','20L','data','%s','cliente','Cliente Y','totalSucata',16,'assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('classe','sucata','motivo','Vencido','qtd',15),jsonb_build_object('classe','novo','marca','Montico','fabricacao','%s','qtd',3))))$q$, hoje, fab1), 'não bate com o total');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-TROCA00000002','tipo','troca','modelo','20LR','data','%s','cliente','Cliente Y','totalSucata',5,'assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('classe','sucata','motivo','Vencido','qtd',5),jsonb_build_object('classe','novo','marca','Montico','fabricacao','%s','qtd',1))))$q$, hoje, fab1), 'não tem troca nem sucata');
  if teste.saldo('20L','S') <> 0 then raise exception 'troca recusada mexeu na sucata'; end if;
  r := public.garrafoes_registrar(jsonb_build_object('id','op-TROCA00000001','tipo','troca','modelo','20L','data',hoje,'cliente','Cliente Y','totalSucata',15,
        'assinatura', teste.ass('Recebimento: 15 sucatas. Entrega: 3 Montico fab. ' || fab1),
        'linhas', jsonb_build_array(jsonb_build_object('classe','sucata','motivo','Vencido','qtd',10), jsonb_build_object('classe','sucata','motivo','Quebrado ou trincado','qtd',5),
                                    jsonb_build_object('classe','novo','marca','Montico','fabricacao',fab1,'qtd',3))));
  if teste.saldo('20L','S') <> 15 or teste.saldo('20L','N|Montico|' || fab1) <> 57 or teste.saldo('20L','N|AGS|' || fab1) <> 40 or teste.saldo('10L','S') <> 0 then
    raise exception 'troca: %', public.garrafoes_saldos_0057('20L'); end if;
  if exists (select 1 from jsonb_array_elements(r -> 'linhas') x where x ->> 'classe' = 'sucata' and (x ? 'marca' or x ? 'fabricante')) then raise exception 'sucata não tem marca'; end if;

  -- RETIRADA: quem recolheu + quantidade; baixa o saldo único da litragem
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RETIRA0000001","tipo":"retirada","modelo":"20L","data":"%s","recolhidoPor":"Montico","contrapartida":"novos","qtd":16}')$q$, hoje), 'tem 15 unidade(s)');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RETIRA0000002","tipo":"retirada","modelo":"20LR","data":"%s","recolhidoPor":"Montico","contrapartida":"sem","qtd":1}')$q$, hoje), 'não tem troca nem sucata');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-RETIRA0000001','tipo','retirada','modelo','20L','data',hoje,'recolhidoPor','Montico','contrapartida','novos','qtd',5));
  if teste.saldo('20L','S') <> 10 or r ->> 'recolhidoPor' <> 'Montico' then raise exception 'retirada'; end if;

  -- RECEBIMENTO VINCULADO (entradas), com foto
  perform teste.como('escritorio:conta');
  perform public.garrafoes_registrar(jsonb_build_object('id','op-RECEBE0000001','tipo','entrada','modelo','20L','data',hoje,'vinculo','op-RETIRA0000001','foto',teste.jpg(),
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','fabricacao',fab1,'qtd',2))));
  if teste.saldo('20L','N|Montico|' || fab1) <> 59 then raise exception 'recebimento vinculado'; end if;

  -- CONTAGEM: sucata (número único) e novos (fabricação encontrada); 20LR sem contagem de sucata
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000001","tipo":"contagem","modelo":"20L","data":"%s","alvo":"sucata","linhas":[{"registrado":10,"contado":12}]}')$q$, hoje), 'justificativa');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000002","tipo":"contagem","modelo":"20LR","data":"%s","alvo":"sucata","justificativa":"x","linhas":[{"registrado":0,"contado":1}]}')$q$, hoje), 'não tem troca nem sucata');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000001","tipo":"contagem","modelo":"20L","data":"%s","alvo":"sucata","justificativa":"pátio","linhas":[{"registrado":9,"contado":12}]}')$q$, hoje), 'mudou para 10');
  perform public.garrafoes_registrar(jsonb_build_object('id','op-CONTA00000001','tipo','contagem','modelo','20L','data',hoje,'alvo','sucata','justificativa','Contagem do pátio',
        'linhas', jsonb_build_array(jsonb_build_object('registrado',10,'contado',12))));
  if teste.saldo('20L','S') <> 12 then raise exception 'contagem sucata'; end if;
  perform public.garrafoes_registrar(jsonb_build_object('id','op-CONTA00000003','tipo','contagem','modelo','10L','data',hoje,'alvo','novos','justificativa','Saldo inicial',
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao',fab0,'registrado',0,'contado',80))));
  if teste.saldo('10L','N|AGS|' || fab0) <> 80 then raise exception 'contagem novos'; end if;

  -- EXCLUSÃO: só a gestão; recalcula; assinatura e foto ficam guardadas
  perform teste.erro($q$select public.garrafoes_excluir('op-TROCA00000001')$q$, 'Só a gestão');
  perform teste.como('escritorio:gestora');
  perform teste.erro($q$select public.garrafoes_excluir('op-TROCA00000001')$q$, 'a sucata com saldo -3');
  perform teste.erro($q$select public.garrafoes_excluir('op-RETIRA0000001')$q$, 'Confirme a exclusão do conjunto');
  perform public.garrafoes_excluir('op-CONTA00000001', 'teste');
  perform public.garrafoes_excluir('op-RETIRA0000001', null, true);
  if teste.saldo('20L','S') <> 15 or teste.saldo('20L','N|Montico|' || fab1) <> 57 then raise exception 'conjunto: %', public.garrafoes_saldos_0057('20L'); end if;
  perform public.garrafoes_excluir('op-TROCA00000001');
  if teste.saldo('20L','S') <> 0 or teste.saldo('20L','N|Montico|' || fab1) <> 60 then raise exception 'excluir troca: %', public.garrafoes_saldos_0057('20L'); end if;
  if teste.conta('g-assin','op-TROCA00000001') <> 1 or teste.conta('g-fotos','op-RECEBE0000001') <> 1 or teste.conta('g-excluidas', null) <> 4 then raise exception 'assinatura/foto/auditoria preservadas'; end if;
  -- excluir a entrada que a venda usou deixaria negativo
  perform teste.erro($q$select public.garrafoes_excluir('op-ENTRADA000003')$q$, 'venda para Mercado X');

  -- setor com o módulo e sem perfil: só consulta
  perform teste.como('setor:expedicao');
  perform teste.erro(format($q$select public.garrafoes_registrar(jsonb_build_object('id','op-SETOR00000001','tipo','saida','modelo','20L','data','%s','cliente','x','assinatura',teste.ass('x'),'linhas',jsonb_build_array(jsonb_build_object('marca','AGS','fabricacao','%s','qtd',1))))$q$, hoje, fab1), 'Seu perfil não registra vendas');
  raise notice 'TODOS OS TESTES PASSARAM';
end $$;
