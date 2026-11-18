-- LEVÍSSIMA · testes das regras do Garrafões no banco (0056): perfis, gravação direta bloqueada, entradas, saídas,
-- troca atômica, retirada, recebimento vinculado, contagem, exclusão com recálculo, idempotência e origem.
-- Termina com 'TODOS OS TESTES PASSARAM'. Ver garrafoes-banco.sql para rodar.
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
  select coalesce((public.garrafoes_saldos_0056(p_modelo) ->> p_chave)::bigint, 0) $$;
create function teste.lote(p_modelo text, p_marca text, p_cod text) returns text language sql as $$
  select 'lt-' || md5(p_modelo || '|' || p_marca || '|' || p_cod) $$;
grant execute on all functions in schema teste to authenticated;

set role authenticated;
do $$
declare r jsonb; l1 text; l2 text; l3 text; hoje text := to_char((now() at time zone 'America/Sao_Paulo')::date, 'YYYY-MM-DD');
  ontem text := to_char((now() at time zone 'America/Sao_Paulo')::date - 1, 'YYYY-MM-DD'); n int;
begin
  -- perfis
  perform teste.como('escritorio:gestora'); if public.garrafoes_eu() ->> 'perfil' <> 'gestao' then raise exception 'gestora'; end if;
  perform teste.como('escritorio:conta'); if public.garrafoes_eu() ->> 'perfil' <> 'consulta' then raise exception 'conta deveria ser consulta'; end if;
  perform teste.como('escritorio:outro'); if public.garrafoes_eu() ->> 'perfil' <> '' then raise exception 'outro'; end if;
  perform teste.como('mestre'); if public.garrafoes_eu() ->> 'perfil' <> 'gestao' then raise exception 'mestre'; end if;

  -- consulta não registra; não-gestão não define perfil
  perform teste.como('escritorio:conta');
  perform teste.erro($q$select public.garrafoes_registrar('{"id":"op-AAAAAAAAAAAA1","tipo":"entrada","modelo":"20L","data":"2026-11-10","linhas":[{"marca":"AGS","codigo":"a1","fabricacao":"2026-10","qtd":10}]}')$q$, 'Seu perfil não registra entradas');
  perform teste.erro($q$select public.garrafoes_perfil_definir('escritorio:conta','entradas')$q$, 'Só a gestão');
  perform teste.erro($q$select public.garrafoes_acessos()$q$, 'Só a gestão');
  -- gravação direta bloqueada
  perform teste.erro($q$insert into public.modulo_docs (modulo,caminho,id,dados) values ('garrafoes','g-ops','op-xxxxxxxxxxxxxx','{}')$q$, 'row-level security');
  perform teste.como('escritorio:gestora');
  perform teste.erro($q$insert into public.modulo_docs (modulo,caminho,id,dados) values ('garrafoes','g-ops','op-xxxxxxxxxxxxxx','{}')$q$, 'row-level security');
  delete from public.modulo_docs where modulo = 'garrafoes' and caminho = 'movimentos';
  get diagnostics n = row_count; if n <> 0 then raise exception 'apagou o controle anterior'; end if;
  update public.modulo_docs set dados = dados || '{"validadeAnos":4}' where modulo = 'garrafoes' and caminho = 'config' and id = 'geral';
  get diagnostics n = row_count; if n <> 1 then raise exception 'gestão deveria mudar o config'; end if;
  perform teste.como('escritorio:conta');
  update public.modulo_docs set dados = dados || '{"validadeAnos":5}' where modulo = 'garrafoes' and caminho = 'config' and id = 'geral';
  get diagnostics n = row_count; if n <> 0 then raise exception 'consulta mudou o config'; end if;

  -- gestão define perfis
  perform teste.como('escritorio:gestora');
  r := public.garrafoes_acessos();
  if jsonb_array_length(r) <> 4 then raise exception 'acessos: %', r; end if;
  perform public.garrafoes_perfil_definir('escritorio:conta', 'entradas');
  perform public.garrafoes_perfil_definir('escritorio:entrega', 'entregas');
  perform teste.erro($q$select public.garrafoes_perfil_definir('escritorio:outro','entregas')$q$, 'não abre o módulo');
  perform teste.erro($q$select public.garrafoes_perfil_definir('escritorio:conta','gestao')$q$, 'Perfil inválido');
  perform teste.como('escritorio:conta'); if public.garrafoes_eu() ->> 'perfil' <> 'entradas' then raise exception 'conta entradas'; end if;

  -- ENTRADAS
  perform teste.como('escritorio:conta');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000001','tipo','entrada','modelo','20L','data',ontem,
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','codigo',' a1 ','fabricacao','2026-10','qtd',100))));
  l1 := teste.lote('20L','AGS','A1');
  if teste.saldo('20L','N|'||l1) <> 100 then raise exception 'saldo l1 %', teste.saldo('20L','N|'||l1); end if;
  if r -> 'por' ->> 'nome' <> 'Contadora' or r ->> 'registradoEm' is null then raise exception 'identificação: %', r; end if;
  -- clique duplo: não duplica
  r := public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000001','tipo','entrada','modelo','20L','data',ontem,
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','codigo','A1','fabricacao','2026-10','qtd',100))));
  if not (r ? 'repetida') or teste.saldo('20L','N|'||l1) <> 100 then raise exception 'duplicou'; end if;
  -- mesmo lote, nova entrada (sem duplicar o cadastro)
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000002','tipo','entrada','modelo','20L','data',hoje,
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','codigo','A1','fabricacao','2026-10','qtd',50))));
  if teste.saldo('20L','N|'||l1) <> 150 then raise exception 'saldo l1 150'; end if;
  select count(*) into n from public.modulo_docs where modulo='garrafoes' and caminho='g-lotes'; if n <> 1 then raise exception 'lote duplicado'; end if;
  -- fabricação diferente no mesmo lote
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000003","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","codigo":"A1","fabricacao":"2026-09","qtd":5}]}')$q$, hoje), 'já está cadastrado com fabricação 10/2026');
  -- mesmo código em outra marca e em outro modelo: independentes
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000004','tipo','entrada','modelo','20L','data',hoje,
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','codigo','A1','fabricacao','2026-09','qtd',40))));
  perform public.garrafoes_registrar(jsonb_build_object('id','op-ENTRADA000005','tipo','entrada','modelo','10L','data',hoje,
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','codigo','A1','fabricacao','2026-08','qtd',30))));
  l2 := teste.lote('20L','Montico','A1'); l3 := teste.lote('10L','AGS','A1');
  if teste.saldo('20L','N|'||l2) <> 40 or teste.saldo('10L','N|'||l3) <> 30 or teste.saldo('20L','N|'||l1) <> 150 then raise exception 'lotes independentes'; end if;
  -- validações
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000006","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","codigo":"B2","fabricacao":"2099-01","qtd":5}]}')$q$, hoje), 'não pode ser depois da data');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000007","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","codigo":"B2","fabricacao":"2026-01","qtd":2.5}]}')$q$, hoje), 'número inteiro');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000008","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","codigo":"B2","fabricacao":"2026-01","qtd":0}]}')$q$, hoje), 'maior que zero');
  perform teste.erro($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000009","tipo":"entrada","modelo":"20L","data":"2099-01-01","linhas":[{"marca":"AGS","codigo":"B2","fabricacao":"2026-01","qtd":2}]}')$q$, 'depois de hoje');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000010","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"Outra","codigo":"B2","fabricacao":"2026-01","qtd":2}]}')$q$, hoje), 'AGS ou Montico');
  -- entradas não faz saída
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA0000000X","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":1}]}')$q$, hoje, l1), 'Seu perfil não registra saídas');

  -- ENTREGAS: saída dividida entre lotes, só da mesma marca, sem negativo
  perform teste.como('escritorio:entrega');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-ENTRADA000011","tipo":"entrada","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","codigo":"C3","fabricacao":"2026-01","qtd":2}]}')$q$, hoje), 'Seu perfil não registra entradas');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":151}]}')$q$, hoje, l1), 'tem 150 unidade(s)');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":100},{"marca":"AGS","lote":"%s","qtd":51}]}')$q$, hoje, l1, l1), 'foram pedidas 151');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":1},{"marca":"Montico","lote":"%s","qtd":1}]}')$q$, hoje, l1, l2), 'uma marca por vez');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":1}]}')$q$, hoje, l3), 'Lote não encontrado neste modelo');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-SAIDA00000001','tipo','saida','modelo','20L','data',hoje,
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','lote',l1,'qtd',20))));
  if teste.saldo('20L','N|'||l1) <> 130 then raise exception 'saida'; end if;
  if r ? 'cliente' then raise exception 'saída não pede destino'; end if;

  -- TROCA: sucata AGS (dois motivos) + novos Montico; soma dos motivos confere com o total; atômica
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-TROCA00000001","tipo":"troca","modelo":"20L","data":"%s","cliente":"Mercado X","totalSucata":26,"linhas":[{"classe":"sucata","fabricante":"AGS","motivo":"Vencido","qtd":20},{"classe":"sucata","fabricante":"AGS","motivo":"Quebrado ou trincado","qtd":5},{"classe":"novo","marca":"Montico","lote":"%s","qtd":5}]}')$q$, hoje, l2), 'não bate com o total');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-TROCA00000001","tipo":"troca","modelo":"20L","data":"%s","cliente":"Mercado X","linhas":[{"classe":"sucata","fabricante":"AGS","motivo":"Extravio","qtd":20},{"classe":"novo","marca":"Montico","lote":"%s","qtd":5}]}')$q$, hoje, l2), 'motivo');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-TROCA00000001","tipo":"troca","modelo":"20L","data":"%s","cliente":"Mercado X","linhas":[{"classe":"sucata","fabricante":"AGS","motivo":"Outro","qtd":20},{"classe":"novo","marca":"Montico","lote":"%s","qtd":5}]}')$q$, hoje, l2), 'Descreva o motivo');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-TROCA00000001","tipo":"troca","modelo":"20L","data":"%s","cliente":"Mercado X","linhas":[{"classe":"sucata","fabricante":"AGS","motivo":"Vencido","qtd":20},{"classe":"novo","marca":"Montico","lote":"%s","qtd":41}]}')$q$, hoje, l2), 'tem 40 unidade(s)');
  if teste.saldo('20L','S|AGS') <> 0 then raise exception 'troca recusada mexeu na sucata'; end if;
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-TROCA00000001","tipo":"troca","modelo":"20L","data":"%s","linhas":[{"classe":"sucata","fabricante":"AGS","motivo":"Vencido","qtd":20},{"classe":"novo","marca":"Montico","lote":"%s","qtd":4}]}')$q$, hoje, l2), 'Informe o cliente');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-TROCA00000001','tipo','troca','modelo','20L','data',hoje,'cliente','Mercado X','totalSucata',27,
        'linhas', jsonb_build_array(
          jsonb_build_object('classe','sucata','fabricante','AGS','motivo','Vencido','qtd',20),
          jsonb_build_object('classe','sucata','fabricante','AGS','motivo','Quebrado ou trincado','qtd',5),
          jsonb_build_object('classe','sucata','fabricante','Montico','motivo','Outro','motivoDesc','Rótulo derretido','qtd',2),
          jsonb_build_object('classe','novo','marca','Montico','lote',l2,'qtd',5),
          jsonb_build_object('classe','novo','marca','AGS','lote',l1,'qtd',1))));
  if teste.saldo('20L','S|AGS') <> 25 or teste.saldo('20L','S|Montico') <> 2 or teste.saldo('20L','N|'||l2) <> 35 or teste.saldo('20L','N|'||l1) <> 129 then
    raise exception 'troca efeitos: %', public.garrafoes_saldos_0056('20L'); end if;
  if teste.saldo('10L','S|AGS') <> 0 then raise exception 'troca vazou de modelo'; end if;

  -- RETIRADA: baixa só a sucata informada; quem recolheu separado do fabricante da sucata
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RETIRA0000001","tipo":"retirada","modelo":"20L","data":"%s","recolhidoPor":"Montico","contrapartida":"novos","linhas":[{"fabricante":"AGS","qtd":26}]}')$q$, hoje), 'tem 25 unidade(s)');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RETIRA0000001","tipo":"retirada","modelo":"20L","data":"%s","recolhidoPor":"Montico","linhas":[{"fabricante":"AGS","qtd":5}]}')$q$, hoje), 'vai entregar novos');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-RETIRA0000001','tipo','retirada','modelo','20L','data',hoje,'recolhidoPor','Montico','contrapartida','novos',
        'linhas', jsonb_build_array(jsonb_build_object('fabricante','AGS','qtd',20), jsonb_build_object('fabricante','Montico','qtd',2))));
  if teste.saldo('20L','S|AGS') <> 5 or teste.saldo('20L','S|Montico') <> 0 or teste.saldo('20L','N|'||l2) <> 35 then raise exception 'retirada efeitos'; end if;
  perform public.garrafoes_registrar(jsonb_build_object('id','op-RETIRA0000002','tipo','retirada','modelo','20L','data',hoje,'recolhidoPor','Recicladora','contrapartida','sem',
        'linhas', jsonb_build_array(jsonb_build_object('fabricante','AGS','qtd',1))));

  -- RECEBIMENTO VINCULADO (perfil entradas), na data real, sem proporção fixa
  perform teste.como('escritorio:conta');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RECEBE0000001","tipo":"entrada","modelo":"20L","data":"%s","vinculo":"op-RETIRA0000002","linhas":[{"marca":"Montico","codigo":"M9","fabricacao":"2026-11","qtd":3}]}')$q$, hoje), 'sem novos em contrapartida');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-RECEBE0000001","tipo":"entrada","modelo":"20L","data":"%s","vinculo":"op-RETIRA0000001","linhas":[{"marca":"Montico","codigo":"M9","fabricacao":"2026-11","qtd":3}]}')$q$, ontem), 'anterior à retirada');
  perform public.garrafoes_registrar(jsonb_build_object('id','op-RECEBE0000001','tipo','entrada','modelo','20L','data',hoje,'vinculo','op-RETIRA0000001',
        'linhas', jsonb_build_array(jsonb_build_object('marca','Montico','codigo','M9','fabricacao','2026-11','qtd',3))));
  if teste.saldo('20L','N|'||teste.lote('20L','Montico','M9')) <> 3 then raise exception 'recebimento'; end if;

  -- CONTAGEM: registrado/contado/diferença; justificativa obrigatória quando há diferença; zero permitido
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000001","tipo":"contagem","modelo":"20L","data":"%s","alvo":"sucata","linhas":[{"fabricante":"AGS","registrado":3,"contado":3}]}')$q$, hoje), 'mudou para 4');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000001","tipo":"contagem","modelo":"20L","data":"%s","alvo":"sucata","linhas":[{"fabricante":"AGS","registrado":4,"contado":0},{"fabricante":"Montico","registrado":0,"contado":0}]}')$q$, hoje), 'justificativa');
  r := public.garrafoes_registrar(jsonb_build_object('id','op-CONTA00000001','tipo','contagem','modelo','20L','data',hoje,'alvo','sucata','justificativa','Contagem do pátio',
        'linhas', jsonb_build_array(jsonb_build_object('fabricante','AGS','registrado',4,'contado',0), jsonb_build_object('fabricante','Montico','registrado',0,'contado',91))));
  if teste.saldo('20L','S|AGS') <> 0 or teste.saldo('20L','S|Montico') <> 91 then raise exception 'contagem sucata'; end if;
  -- contagem de novos com lote encontrado no físico (saldo inicial)
  r := public.garrafoes_registrar(jsonb_build_object('id','op-CONTA00000002','tipo','contagem','modelo','20LR','data',hoje,'alvo','novos','justificativa','Saldo inicial',
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','codigo','R1','fabricacao','2026-06','registrado',0,'contado',124))));
  if teste.saldo('20LR','N|'||teste.lote('20LR','AGS','R1')) <> 124 then raise exception 'contagem novos'; end if;
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-CONTA00000003","tipo":"contagem","modelo":"20L","data":"%s","alvo":"novos","linhas":[{"lote":"%s","registrado":129,"contado":129},{"lote":"%s","registrado":129,"contado":129}]}')$q$, hoje, l1, l1), 'duas vezes');

  -- EXCLUSÃO: só a gestão
  perform teste.erro($q$select public.garrafoes_excluir('op-SAIDA00000001')$q$, 'Só a gestão');
  perform teste.como('escritorio:gestora');
  -- excluir a entrada deixaria o lote negativo? l1: entradas 100+50, saída 20, troca 1 → 129. Excluir a de 100 → 29 (ok). Excluir a de 100 e a de 50? tentar a do lote Montico A1 (40): saldo 35, a entrada é 40 → −5
  perform teste.erro($q$select public.garrafoes_excluir('op-ENTRADA000004')$q$, 'saldo -5');
  perform teste.erro($q$select public.garrafoes_excluir('op-ENTRADA000004')$q$, 'troca com Mercado X');
  -- retirada com recebimento vinculado: pede o conjunto
  perform teste.erro($q$select public.garrafoes_excluir('op-RETIRA0000001')$q$, 'Confirme a exclusão do conjunto');
  -- excluir a troca: precisa desfazer a contagem antes? sucata Montico: troca +2, retirada −2, contagem +91 = 91 → sem a troca 89 (ok); AGS: 25−20−1−4 = 0 → sem a troca −25: recusa
  perform teste.erro($q$select public.garrafoes_excluir('op-TROCA00000001')$q$, 'a sucata AGS com saldo -25');
  -- excluir saída devolve ao lote
  r := public.garrafoes_excluir('op-SAIDA00000001', 'Lançada errado');
  if teste.saldo('20L','N|'||l1) <> 149 then raise exception 'excluir saída'; end if;
  select count(*) into n from public.modulo_docs where modulo='garrafoes' and caminho='g-excluidas' and id='op-SAIDA00000001' and dados->>'motivo' = 'Lançada errado' and dados->'excluidoPor'->>'nome' = 'Gestora';
  if n <> 1 then raise exception 'auditoria da exclusão'; end if;
  -- reenviar a operação excluída não volta
  perform teste.como('escritorio:entrega');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SAIDA00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":20}]}')$q$, hoje, l1), 'excluída');
  -- conjunto retirada + recebimento
  perform teste.como('escritorio:gestora');
  r := public.garrafoes_excluir('op-RETIRA0000001', null, true);
  if jsonb_array_length(r -> 'excluidas') <> 2 then raise exception 'conjunto: %', r; end if;
  if teste.saldo('20L','S|AGS') <> 20 or teste.saldo('20L','S|Montico') <> 93 then raise exception 'conjunto saldos %', public.garrafoes_saldos_0056('20L'); end if;
  select count(*) into n from public.modulo_docs where modulo='garrafoes' and caminho='g-lotes' and id = teste.lote('20L','Montico','M9');
  if n <> 0 then raise exception 'lote sem lançamento ficou'; end if;
  -- excluir a contagem desfaz o ajuste
  perform public.garrafoes_excluir('op-CONTA00000001');
  if teste.saldo('20L','S|AGS') <> 24 or teste.saldo('20L','S|Montico') <> 2 then raise exception 'excluir contagem %', public.garrafoes_saldos_0056('20L'); end if;
  -- excluir a troca agora: AGS 24 − 25 = −1 por causa da retirada de 1 à Recicladora
  perform teste.erro($q$select public.garrafoes_excluir('op-TROCA00000001')$q$, 'retirada de');
  perform public.garrafoes_excluir('op-RETIRA0000002');
  perform public.garrafoes_excluir('op-TROCA00000001');
  if teste.saldo('20L','S|AGS') <> 0 or teste.saldo('20L','N|'||l2) <> 40 or teste.saldo('20L','N|'||l1) <> 150 then raise exception 'excluir troca %', public.garrafoes_saldos_0056('20L'); end if;

  -- integração futura: a mesma origem não conta duas vezes
  perform teste.como('escritorio:entrega');
  perform public.garrafoes_registrar(jsonb_build_object('id','op-PEDIDO0000001','tipo','saida','modelo','20L','data',hoje,'origem',jsonb_build_object('sistema','pedidos','ref','ped-123'),
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','lote',l1,'qtd',10))));
  r := public.garrafoes_registrar(jsonb_build_object('id','op-PEDIDO0000002','tipo','saida','modelo','20L','data',hoje,'origem',jsonb_build_object('sistema','pedidos','ref','ped-123'),
        'linhas', jsonb_build_array(jsonb_build_object('marca','AGS','lote',l1,'qtd',10))));
  if not (r ? 'repetida') or teste.saldo('20L','N|'||l1) <> 140 then raise exception 'origem duplicada'; end if;

  -- setor com o módulo e sem perfil: só consulta
  perform teste.como('setor:expedicao');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-SETOR00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":1}]}')$q$, hoje, l1), 'Seu perfil não registra saídas');
  -- quem não tem o módulo
  perform teste.como('escritorio:outro');
  perform teste.erro(format($q$select public.garrafoes_registrar('{"id":"op-OUTRO00000001","tipo":"saida","modelo":"20L","data":"%s","linhas":[{"marca":"AGS","lote":"%s","qtd":1}]}')$q$, hoje, l1), 'Sem acesso ao módulo');
  raise notice 'TODOS OS TESTES PASSARAM';
end $$;
