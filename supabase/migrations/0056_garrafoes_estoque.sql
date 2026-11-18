-- LEVÍSSIMA · 0056: módulo Garrafões refeito (pedido de 17/11/2026).
--
-- * Estoque de vasilhames NOVOS por modelo + marca + lote e de SUCATA por modelo + fabricante, em unidades.
--   Modelos: 20L, 20LR (20 L com rosca) e 10L. Marcas/fabricantes: AGS e Montico.
-- * Os dados ficam em modulo_docs (módulo 'garrafoes'), o que dá o tempo real entre os aparelhos e o histórico de
--   alterações (auditoria_modulo_docs_0036):
--     g-lotes/<id>      lote de novos: modelo, marca, código, fabricação (mês/ano). Id = modelo + marca + código.
--     g-ops/<id>        uma operação com as suas linhas (efeitos): entrada, saída, troca, retirada ou contagem.
--     g-excluidas/<id>  operação excluída pela gestão, com o conteúdo, quem e quando (não conta mais no saldo).
--     g-perfis/perfis   perfil de cada acesso que usa o módulo: consulta, entradas ou entregas.
--     config/geral      validade (anos) e mínimo/capacidade de cada modelo (o mesmo documento de antes).
--   O saldo é a soma das linhas das operações (novos: lote; sucata: fabricante). Nada é sobrescrito.
-- * Perfis: gestão = senha mestre ou acesso com "Gerencia" no módulo Garrafões (Cadastros › Acesso ao app); quem só
--   "Usa" o módulo tem o perfil escolhido pela gestão no próprio módulo (sem escolha: só consulta).
--     entradas: entrada de novos (com ou sem vínculo a uma retirada) e contagem física.
--     entregas: saída de novos, troca com cliente e retirada de sucata pelo fabricante.
--     gestão: tudo, mais exclusão, perfis, configuração e exportação.
-- * Gravação só pelas funções abaixo (SECURITY DEFINER): conferem o perfil, travam o modelo (pg_advisory_xact_lock),
--   validam de novo o saldo (nenhum lote nem fabricante fica negativo), gravam tudo de uma vez (a troca grava a
--   entrada da sucata e a saída dos novos juntas) e não duplicam: o mesmo id de operação devolve o que já existe.
--   Gravação direta em modulo_docs do módulo fica bloqueada, menos o config/geral pela gestão.
-- * Os lançamentos do controle anterior (movimentos/*) ficam guardados como estão e não entram mais no saldo; o saldo
--   inicial de cada modelo nasce da primeira contagem física.
-- * Integrações futuras (vendas dos pedidos, recebimento de insumos): a operação aceita "origem" {sistema, ref};
--   a mesma origem não é contada duas vezes.

-- ---------------------------------------------------------------- perfil de quem está usando
create or replace function public.garrafoes_perfil_0056()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with m as (select coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb) as j)
  select case
    when j ->> 'papel' = 'mestre' then 'gestao'
    when coalesce(j ->> 'papel', '') not in ('equipe', 'setor') then ''
    when jsonb_typeof(j -> 'modulos') = 'array' and (j -> 'modulos') ? 'garrafoes:gerir' then 'gestao'
    when jsonb_typeof(j -> 'modulos') = 'array' and (j -> 'modulos') ? 'garrafoes' then
      coalesce((select case when d.dados -> 'refs' ->> (j ->> 'ref') in ('entradas', 'entregas') then d.dados -> 'refs' ->> (j ->> 'ref') end
                  from public.modulo_docs d
                 where d.modulo = 'garrafoes' and d.caminho = 'g-perfis' and d.id = 'perfis'), 'consulta')
    else ''
  end
  from m;
$$;
revoke execute on function public.garrafoes_perfil_0056() from public, anon;
grant execute on function public.garrafoes_perfil_0056() to authenticated;

create or replace function public.garrafoes_eu()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object('perfil', public.garrafoes_perfil_0056(),
                            'ref', coalesce(auth.jwt() -> 'app_metadata' ->> 'ref', ''),
                            'nome', coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', ''));
$$;
revoke execute on function public.garrafoes_eu() from public, anon;
grant execute on function public.garrafoes_eu() to authenticated;

-- ---------------------------------------------------------------- auxiliares (só usadas pelas funções do módulo)
-- número inteiro de 0 a 1.000.000 (número ou texto só com dígitos); qualquer outra coisa: null
create or replace function public.garrafoes_int_0056(v jsonb)
returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  n numeric;
begin
  if v is null then return null; end if;
  if jsonb_typeof(v) = 'number' then n := (v #>> '{}')::numeric;
  elsif jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\s*[0-9]{1,7}\s*$' then n := btrim(v #>> '{}')::numeric;
  else return null;
  end if;
  if n <> trunc(n) or n < 0 or n > 1000000 then return null; end if;
  return n::integer;
end $$;
revoke execute on function public.garrafoes_int_0056(jsonb) from public, anon, authenticated;

-- saldo de cada chave do modelo ('N|<lote>' para novos, 'S|<fabricante>' para sucata), sem as operações p_sem
create or replace function public.garrafoes_saldos_0056(p_modelo text, p_sem text[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(k, s), '{}'::jsonb) from (
    select case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'lote') else 'S|' || (l ->> 'fabricante') end as k,
           sum((l ->> 'qtd')::bigint) as s
      from public.modulo_docs d
     cross join lateral jsonb_array_elements(case when jsonb_typeof(d.dados -> 'linhas') = 'array' then d.dados -> 'linhas' else '[]'::jsonb end) l
     where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.dados ->> 'modelo' = p_modelo
       and not (d.id = any(coalesce(p_sem, '{}')))
     group by 1) x;
$$;
revoke execute on function public.garrafoes_saldos_0056(text, text[]) from public, anon, authenticated;

-- nome de uma chave de saldo para as mensagens
create or replace function public.garrafoes_nome_chave_0056(p_chave text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_chave like 'S|%' then 'a sucata ' || substr(p_chave, 3)
    else coalesce((select 'o lote ' || (d.dados ->> 'codigo') || ' (' || (d.dados ->> 'marca') || ')'
                     from public.modulo_docs d where d.modulo = 'garrafoes' and d.caminho = 'g-lotes' and d.id = substr(p_chave, 3)), 'um lote')
  end;
$$;
revoke execute on function public.garrafoes_nome_chave_0056(text) from public, anon, authenticated;

create or replace function public.garrafoes_mes_0056(p text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select substr(p, 6, 2) || '/' || substr(p, 1, 4); $$;
revoke execute on function public.garrafoes_mes_0056(text) from public, anon, authenticated;

-- linhas de novos que SAEM (saída ou troca): confere lote, marca e quantidade, junta o mesmo lote e confere o saldo.
-- Devolve as linhas prontas para gravar (quantidade negativa).
create or replace function public.garrafoes_novos_saindo_0056(p_modelo text, p_linhas jsonb, p_mesma_marca boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  l jsonb;
  v_lote text; v_qtd integer; v_doc jsonb; v_marca text := null;
  v_pedido jsonb := '{}'::jsonb;
  v_info jsonb := '{}'::jsonb;
  v_saldos jsonb := public.garrafoes_saldos_0056(p_modelo);
  v_out jsonb := '[]'::jsonb;
  k text; v_s bigint; v_p bigint;
begin
  for l in select * from jsonb_array_elements(p_linhas) loop
    v_lote := l ->> 'lote';
    if v_lote is null or v_lote !~ '^lt-[0-9a-f]{32}$' then raise exception 'Escolha o lote de cada linha de novos.'; end if;
    select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-lotes' and id = v_lote;
    if not found or v_doc ->> 'modelo' <> p_modelo then raise exception 'Lote não encontrado neste modelo. Atualize a página e escolha de novo.'; end if;
    if coalesce(l ->> 'marca', v_doc ->> 'marca') <> v_doc ->> 'marca' then raise exception 'O lote % não é da marca %.', v_doc ->> 'codigo', l ->> 'marca'; end if;
    if p_mesma_marca then
      if v_marca is null then v_marca := v_doc ->> 'marca';
      elsif v_marca <> v_doc ->> 'marca' then raise exception 'A saída é de uma marca por vez. Registre a outra marca em outra saída.';
      end if;
    end if;
    v_qtd := public.garrafoes_int_0056(l -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de novos de cada lote (número inteiro maior que zero).'; end if;
    v_pedido := v_pedido || jsonb_build_object(v_lote, coalesce((v_pedido ->> v_lote)::bigint, 0) + v_qtd);
    v_info := v_info || jsonb_build_object(v_lote, v_doc);
  end loop;
  for k in select jsonb_object_keys(v_pedido) loop
    v_s := coalesce((v_saldos ->> ('N|' || k))::bigint, 0);
    v_p := (v_pedido ->> k)::bigint;
    if v_p > v_s then
      raise exception 'O lote % (%) tem % unidade(s) disponível(is); foram pedidas %.', v_info -> k ->> 'codigo', v_info -> k ->> 'marca', v_s, v_p;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', v_info -> k ->> 'marca', 'lote', k,
      'codigo', v_info -> k ->> 'codigo', 'fabricacao', v_info -> k ->> 'fabricacao', 'qtd', -v_p));
  end loop;
  return v_out;
end $$;
revoke execute on function public.garrafoes_novos_saindo_0056(text, jsonb, boolean) from public, anon, authenticated;

-- lote de novos pelo código: devolve o id; cria se não existir; recusa fabricação diferente da cadastrada
create or replace function public.garrafoes_lote_0056(p_modelo text, p_marca text, p_codigo text, p_fab text, p_data date)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cod text := upper(regexp_replace(btrim(coalesce(p_codigo, '')), '\s+', ' ', 'g'));
  v_id text; v_doc jsonb;
  v_meta jsonb := coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb);
begin
  if p_marca is null or p_marca not in ('AGS', 'Montico') then raise exception 'Escolha a marca: AGS ou Montico.'; end if;
  if length(v_cod) < 1 or length(v_cod) > 40 then raise exception 'Informe a identificação do lote (até 40 caracteres).'; end if;
  if p_fab is null or p_fab !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Informe o mês e o ano de fabricação do lote %.', v_cod; end if;
  if p_fab < '2015-01' then raise exception 'Fabricação muito antiga (%). Confira o mês e o ano.', public.garrafoes_mes_0056(p_fab); end if;
  if p_fab > to_char(p_data, 'YYYY-MM') then
    raise exception 'A fabricação do lote % (%) não pode ser depois da data da movimentação.', v_cod, public.garrafoes_mes_0056(p_fab);
  end if;
  v_id := 'lt-' || md5(p_modelo || '|' || p_marca || '|' || v_cod);
  select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-lotes' and id = v_id;
  if found then
    if v_doc ->> 'fabricacao' <> p_fab then
      raise exception 'O lote % da % já está cadastrado com fabricação %. Confira o lote ou a fabricação.', v_cod, p_marca, public.garrafoes_mes_0056(v_doc ->> 'fabricacao');
    end if;
  else
    v_doc := jsonb_build_object('modelo', p_modelo, 'marca', p_marca, 'codigo', v_cod, 'fabricacao', p_fab,
      'criadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'criadoPor', jsonb_strip_nulls(jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome')));
    insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-lotes', v_id, v_doc);
  end if;
  return jsonb_build_object('id', v_id, 'codigo', v_cod, 'marca', p_marca, 'fabricacao', p_fab);
end $$;
revoke execute on function public.garrafoes_lote_0056(text, text, text, text, date) from public, anon, authenticated;

-- ---------------------------------------------------------------- registrar uma operação
-- p: { id: 'op-…' (gerado ao abrir o formulário), tipo, modelo, data 'AAAA-MM-DD', obs?, origem?, linhas: [...], … }
--   entrada:  linhas [{marca, codigo, fabricacao 'AAAA-MM', qtd}] (um lote) e vinculo? (id da retirada com novos)
--   saida:    linhas [{marca, lote, qtd}] (uma marca, um ou mais lotes)
--   troca:    cliente, totalSucata, linhas [{classe 'sucata', fabricante, motivo, motivoDesc?, qtd}, {classe 'novo', marca, lote, qtd}]
--   retirada: recolhidoPor, contrapartida ('novos' | 'sem'), linhas [{fabricante, qtd}]
--   contagem: alvo ('novos' | 'sucata'), justificativa, linhas [{lote | marca+codigo+fabricacao, registrado, contado}]
--             ou [{fabricante, registrado, contado}]
create or replace function public.garrafoes_registrar(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_perfil text := public.garrafoes_perfil_0056();
  v_meta jsonb := coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb);
  v_id text := p ->> 'id';
  v_tipo text := p ->> 'tipo';
  v_modelo text := p ->> 'modelo';
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_data date;
  v_doc jsonb;
  v_linhas jsonb := '[]'::jsonb;
  v_saldos jsonb;
  l jsonb;
  v_lote jsonb; v_lote_id text;
  v_fab text; v_qtd integer; v_motivo text; v_desc text;
  v_obs text := nullif(left(btrim(coalesce(p ->> 'obs', '')), 500), '');
  v_cli text; v_rec text; v_contra text; v_vinc text; v_vdoc jsonb; v_just text; v_alvo text;
  v_suc jsonb := '{}'::jsonb; v_sinfo jsonb := '{}'::jsonb;
  v_tot integer := 0; v_tot_inf integer;
  v_nov jsonb := '[]'::jsonb;
  v_reg integer; v_cont integer; v_atual bigint; v_dif boolean := false;
  v_vistas text[] := '{}'; v_k text;
  v_origem jsonb := null;
  k text;
begin
  if v_perfil = '' then raise exception 'Sem acesso ao módulo Garrafões.'; end if;
  if v_id is null or v_id !~ '^op-[A-Za-z0-9]{12,40}$' then raise exception 'Identificador da operação inválido. Abra o formulário de novo.'; end if;
  if v_modelo is null or v_modelo not in ('20L', '20LR', '10L') then raise exception 'Modelo inválido.'; end if;
  if v_tipo is null or v_tipo not in ('entrada', 'saida', 'troca', 'retirada', 'contagem') then raise exception 'Tipo de operação inválido.'; end if;
  if v_tipo in ('entrada', 'contagem') and v_perfil not in ('entradas', 'gestao') then
    raise exception 'Seu perfil não registra %. Fale com a gestão do módulo.', case v_tipo when 'entrada' then 'entradas de novos' else 'contagens físicas' end;
  end if;
  if v_tipo in ('saida', 'troca', 'retirada') and v_perfil not in ('entregas', 'gestao') then
    raise exception 'Seu perfil não registra %. Fale com a gestão do módulo.',
      case v_tipo when 'saida' then 'saídas de novos' when 'troca' then 'trocas com cliente' else 'retiradas de sucata' end;
  end if;
  if jsonb_typeof(p -> 'linhas') <> 'array' or jsonb_array_length(p -> 'linhas') < 1 then raise exception 'Preencha ao menos uma linha.'; end if;
  if jsonb_array_length(p -> 'linhas') > 40 then raise exception 'Linhas demais numa operação só.'; end if;

  -- uma operação por vez em cada modelo: o saldo conferido é o que vale na hora de gravar
  perform pg_advisory_xact_lock(hashtext('garrafoes:' || v_modelo));

  -- o mesmo envio de novo (clique duplo, internet que voltou): devolve o que já foi gravado, sem duplicar
  select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = v_id;
  if found then return v_doc || jsonb_build_object('id', v_id, 'repetida', true); end if;
  if exists (select 1 from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-excluidas' and id = v_id) then
    raise exception 'Esta operação já foi registrada e depois excluída pela gestão.';
  end if;

  -- integração futura: a mesma origem (ex.: o mesmo pedido) não entra duas vezes
  if p ? 'origem' and jsonb_typeof(p -> 'origem') <> 'null' then
    if jsonb_typeof(p -> 'origem') <> 'object' or coalesce(p -> 'origem' ->> 'sistema', '') not in ('pedidos', 'recebimento_insumos')
       or coalesce(p -> 'origem' ->> 'ref', '') !~ '^[A-Za-z0-9._:-]{1,120}$' then
      raise exception 'Origem da operação inválida.';
    end if;
    v_origem := jsonb_build_object('sistema', p -> 'origem' ->> 'sistema', 'ref', p -> 'origem' ->> 'ref');
    select d.id, d.dados into k, v_doc from public.modulo_docs d
     where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.dados -> 'origem' = v_origem limit 1;
    if found then return v_doc || jsonb_build_object('id', k, 'repetida', true); end if;
  end if;

  begin v_data := (p ->> 'data')::date; exception when others then v_data := null; end;
  if v_data is null then raise exception 'Informe a data da movimentação.'; end if;
  if v_data > v_hoje then raise exception 'A data da movimentação não pode ser depois de hoje.'; end if;
  if v_data < v_hoje - 400 then raise exception 'Data muito antiga. Confira a data da movimentação.'; end if;

  if v_tipo = 'entrada' then
    if jsonb_array_length(p -> 'linhas') <> 1 then raise exception 'A entrada é de um lote por vez.'; end if;
    l := p -> 'linhas' -> 0;
    v_qtd := public.garrafoes_int_0056(l -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade em unidades (número inteiro maior que zero).'; end if;
    v_vinc := nullif(btrim(coalesce(p ->> 'vinculo', '')), '');
    if v_vinc is not null then
      select dados into v_vdoc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = v_vinc;
      if not found or v_vdoc ->> 'tipo' <> 'retirada' or v_vdoc ->> 'modelo' <> v_modelo or coalesce(v_vdoc ->> 'contrapartida', '') <> 'novos' then
        raise exception 'A retirada vinculada não foi encontrada neste modelo (ou foi registrada sem novos em contrapartida).';
      end if;
      if v_data < (v_vdoc ->> 'data')::date then
        raise exception 'O recebimento não pode ter data anterior à retirada vinculada (%).', to_char((v_vdoc ->> 'data')::date, 'DD/MM/YYYY');
      end if;
    end if;
    v_lote := public.garrafoes_lote_0056(v_modelo, l ->> 'marca', l ->> 'codigo', l ->> 'fabricacao', v_data);
    v_linhas := jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', v_lote ->> 'marca', 'lote', v_lote ->> 'id',
      'codigo', v_lote ->> 'codigo', 'fabricacao', v_lote ->> 'fabricacao', 'qtd', v_qtd));

  elsif v_tipo = 'saida' then
    v_linhas := public.garrafoes_novos_saindo_0056(v_modelo, p -> 'linhas', true);

  elsif v_tipo = 'troca' then
    v_cli := nullif(left(btrim(coalesce(p ->> 'cliente', '')), 120), '');
    if v_cli is null then raise exception 'Informe o cliente da troca.'; end if;
    for l in select * from jsonb_array_elements(p -> 'linhas') loop
      if l ->> 'classe' = 'sucata' then
        if coalesce(l ->> 'fabricante', '') not in ('AGS', 'Montico') then raise exception 'Escolha o fabricante de cada linha de sucata: AGS ou Montico.'; end if;
        v_motivo := l ->> 'motivo';
        if v_motivo is null or v_motivo not in ('Quebrado ou trincado', 'Vencido', 'Vazamento', 'Contaminado ou sujo', 'Outro') then
          raise exception 'Escolha o motivo de cada linha de sucata.';
        end if;
        v_desc := nullif(left(btrim(coalesce(l ->> 'motivoDesc', '')), 120), '');
        if v_motivo = 'Outro' and (v_desc is null or length(v_desc) < 3) then raise exception 'Descreva o motivo "Outro" da sucata.'; end if;
        if v_motivo <> 'Outro' then v_desc := null; end if;
        v_qtd := public.garrafoes_int_0056(l -> 'qtd');
        if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de cada linha de sucata (número inteiro maior que zero).'; end if;
        v_k := (l ->> 'fabricante') || '|' || v_motivo || '|' || coalesce(lower(v_desc), '');
        v_suc := v_suc || jsonb_build_object(v_k, coalesce((v_suc ->> v_k)::integer, 0) + v_qtd);
        v_sinfo := v_sinfo || jsonb_build_object(v_k, jsonb_strip_nulls(jsonb_build_object('fabricante', l ->> 'fabricante', 'motivo', v_motivo, 'motivoDesc', v_desc)));
        v_tot := v_tot + v_qtd;
      elsif l ->> 'classe' = 'novo' then
        v_nov := v_nov || jsonb_build_array(l);
      else
        raise exception 'Linha da troca sem tipo (sucata ou novo).';
      end if;
    end loop;
    if v_tot = 0 then raise exception 'Informe as sucatas recebidas do cliente.'; end if;
    if jsonb_array_length(v_nov) = 0 then raise exception 'Informe os novos entregues ao cliente.'; end if;
    if p ? 'totalSucata' then
      v_tot_inf := public.garrafoes_int_0056(p -> 'totalSucata');
      if v_tot_inf is null or v_tot_inf <> v_tot then
        raise exception 'A soma dos motivos (%) não bate com o total de sucatas recebidas (%).', v_tot, coalesce(p ->> 'totalSucata', '?');
      end if;
    end if;
    for k in select jsonb_object_keys(v_suc) loop
      v_linhas := v_linhas || jsonb_build_array((v_sinfo -> k) || jsonb_build_object('classe', 'sucata', 'qtd', (v_suc ->> k)::integer));
    end loop;
    v_linhas := v_linhas || public.garrafoes_novos_saindo_0056(v_modelo, v_nov, false);

  elsif v_tipo = 'retirada' then
    v_rec := nullif(left(btrim(coalesce(p ->> 'recolhidoPor', '')), 80), '');
    if v_rec is null or length(v_rec) < 2 then raise exception 'Informe quem recolheu a sucata.'; end if;
    v_contra := p ->> 'contrapartida';
    if v_contra is null or v_contra not in ('novos', 'sem') then raise exception 'Informe se o fabricante vai entregar novos em troca desta sucata.'; end if;
    for l in select * from jsonb_array_elements(p -> 'linhas') loop
      if coalesce(l ->> 'fabricante', '') not in ('AGS', 'Montico') then raise exception 'Escolha o fabricante da sucata de cada linha: AGS ou Montico.'; end if;
      v_qtd := public.garrafoes_int_0056(l -> 'qtd');
      if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de sucata de cada linha (número inteiro maior que zero).'; end if;
      v_suc := v_suc || jsonb_build_object(l ->> 'fabricante', coalesce((v_suc ->> (l ->> 'fabricante'))::integer, 0) + v_qtd);
    end loop;
    v_saldos := public.garrafoes_saldos_0056(v_modelo);
    for k in select jsonb_object_keys(v_suc) loop
      v_atual := coalesce((v_saldos ->> ('S|' || k))::bigint, 0);
      if (v_suc ->> k)::bigint > v_atual then
        raise exception 'A sucata % tem % unidade(s) em estoque; a retirada informa %.', k, v_atual, v_suc ->> k;
      end if;
      v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('classe', 'sucata', 'fabricante', k, 'qtd', -(v_suc ->> k)::integer));
    end loop;

  elsif v_tipo = 'contagem' then
    v_alvo := p ->> 'alvo';
    if v_alvo is null or v_alvo not in ('novos', 'sucata') then raise exception 'Escolha o que foi contado: novos ou sucata.'; end if;
    v_just := nullif(left(btrim(coalesce(p ->> 'justificativa', '')), 500), '');
    v_saldos := public.garrafoes_saldos_0056(v_modelo);
    for l in select * from jsonb_array_elements(p -> 'linhas') loop
      v_cont := public.garrafoes_int_0056(l -> 'contado');
      if v_cont is null then raise exception 'Informe a quantidade contada (zero se não houver nenhum).'; end if;
      v_reg := public.garrafoes_int_0056(l -> 'registrado');
      if v_reg is null then v_reg := 0; end if;
      if v_alvo = 'novos' then
        if coalesce(l ->> 'lote', '') <> '' then
          select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-lotes' and id = l ->> 'lote';
          if not found or v_doc ->> 'modelo' <> v_modelo then raise exception 'Lote não encontrado neste modelo. Abra a contagem de novo.'; end if;
          v_lote := jsonb_build_object('id', l ->> 'lote', 'codigo', v_doc ->> 'codigo', 'marca', v_doc ->> 'marca', 'fabricacao', v_doc ->> 'fabricacao');
        else
          v_lote := public.garrafoes_lote_0056(v_modelo, l ->> 'marca', l ->> 'codigo', l ->> 'fabricacao', v_data);
        end if;
        v_k := 'N|' || (v_lote ->> 'id');
      else
        if coalesce(l ->> 'fabricante', '') not in ('AGS', 'Montico') then raise exception 'Escolha o fabricante da sucata contada.'; end if;
        v_k := 'S|' || (l ->> 'fabricante');
      end if;
      if v_k = any(v_vistas) then raise exception 'O mesmo % aparece duas vezes na contagem.', case when v_alvo = 'novos' then 'lote' else 'fabricante' end; end if;
      v_vistas := v_vistas || v_k;
      v_atual := coalesce((v_saldos ->> v_k)::bigint, 0);
      if v_atual <> v_reg then
        raise exception 'O saldo % mudou para % enquanto você contava (outro registro foi feito). Abra a contagem de novo.',
          case when v_alvo = 'novos' then 'do lote ' || (v_lote ->> 'codigo') || ' (' || (v_lote ->> 'marca') || ')' else 'da sucata ' || (l ->> 'fabricante') end, v_atual;
      end if;
      if v_cont <> v_atual then v_dif := true; end if;
      if v_alvo = 'novos' then
        v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', v_lote ->> 'marca', 'lote', v_lote ->> 'id',
          'codigo', v_lote ->> 'codigo', 'fabricacao', v_lote ->> 'fabricacao', 'registrado', v_atual, 'contado', v_cont, 'qtd', v_cont - v_atual));
      else
        v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('classe', 'sucata', 'fabricante', l ->> 'fabricante',
          'registrado', v_atual, 'contado', v_cont, 'qtd', v_cont - v_atual));
      end if;
    end loop;
    if v_dif and (v_just is null or length(v_just) < 3) then raise exception 'Explique na justificativa por que a contagem deu diferente do registrado.'; end if;
  end if;

  v_doc := jsonb_strip_nulls(jsonb_build_object(
    'tipo', v_tipo, 'modelo', v_modelo, 'data', to_char(v_data, 'YYYY-MM-DD'),
    'registradoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'por', jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome', 'papel', v_meta ->> 'papel'),
    'perfil', v_perfil, 'cliente', v_cli, 'recolhidoPor', v_rec, 'contrapartida', v_contra, 'vinculo', v_vinc,
    'alvo', v_alvo, 'justificativa', v_just, 'obs', v_obs, 'origem', v_origem, 'linhas', v_linhas));
  insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-ops', v_id, v_doc);
  return v_doc || jsonb_build_object('id', v_id);
end $$;
revoke execute on function public.garrafoes_registrar(jsonb) from public, anon;
grant execute on function public.garrafoes_registrar(jsonb) to authenticated;

-- ---------------------------------------------------------------- excluir (só a gestão)
-- Desfaz os efeitos da operação (e, numa retirada com recebimentos vinculados, do conjunto, quando p_conjunto).
-- Recusa se algum lote ou fabricante ficar negativo, dizendo o que corrigir antes. Guarda o conteúdo em g-excluidas.
create or replace function public.garrafoes_excluir(p_id text, p_motivo text default null, p_conjunto boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_doc jsonb; v_modelo text;
  v_ids text[]; v_lig text[];
  v_saldos jsonb; k text; v_s bigint; v_dep text;
  v_meta jsonb := coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb);
  v_motivo text := nullif(left(btrim(coalesce(p_motivo, '')), 300), '');
  v_agora text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_lotes text[];
  r record;
begin
  if public.garrafoes_perfil_0056() <> 'gestao' then raise exception 'Só a gestão do módulo exclui lançamentos.'; end if;
  select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = p_id;
  if not found then raise exception 'Lançamento não encontrado (talvez já tenha sido excluído).'; end if;
  v_modelo := v_doc ->> 'modelo';
  perform pg_advisory_xact_lock(hashtext('garrafoes:' || v_modelo));
  select dados into v_doc from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = p_id;
  if not found then raise exception 'Lançamento não encontrado (talvez já tenha sido excluído).'; end if;

  v_ids := array[p_id];
  if v_doc ->> 'tipo' = 'retirada' then
    select array_agg(id order by id) into v_lig from public.modulo_docs
     where modulo = 'garrafoes' and caminho = 'g-ops' and dados ->> 'vinculo' = p_id;
    if v_lig is not null then
      if not coalesce(p_conjunto, false) then
        raise exception 'Esta retirada tem % recebimento(s) de novos vinculado(s). Confirme a exclusão do conjunto.', cardinality(v_lig);
      end if;
      v_ids := v_ids || v_lig;
    end if;
  end if;

  v_saldos := public.garrafoes_saldos_0056(v_modelo, v_ids);
  for k in
    select distinct case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'lote') else 'S|' || (l ->> 'fabricante') end
      from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
     where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.id = any(v_ids)
  loop
    v_s := coalesce((v_saldos ->> k)::bigint, 0);
    if v_s < 0 then
      select string_agg(x.txt, '; ') into v_dep from (
        select (case d.dados ->> 'tipo' when 'saida' then 'saída' when 'troca' then 'troca com ' || coalesce(d.dados ->> 'cliente', 'cliente')
                  when 'retirada' then 'retirada' when 'contagem' then 'contagem' else d.dados ->> 'tipo' end)
               || ' de ' || to_char((d.dados ->> 'data')::date, 'DD/MM/YYYY') || ' (' || abs((l ->> 'qtd')::bigint) || ')' as txt
          from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
         where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.dados ->> 'modelo' = v_modelo and not (d.id = any(v_ids))
           and (l ->> 'qtd')::bigint < 0
           and case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'lote') else 'S|' || (l ->> 'fabricante') end = k
         order by d.dados ->> 'data' desc, d.dados ->> 'registradoEm' desc
         limit 5) x;
      raise exception 'Excluir deixaria % com saldo %. Exclua ou corrija antes: %.', public.garrafoes_nome_chave_0056(k), v_s, coalesce(v_dep, 'os lançamentos que usaram esse saldo');
    end if;
  end loop;

  select array_agg(distinct l ->> 'lote') into v_lotes
    from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
   where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.id = any(v_ids) and l ->> 'classe' = 'novo';

  for r in select id, dados from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = any(v_ids) loop
    insert into public.modulo_docs (modulo, caminho, id, dados)
    values ('garrafoes', 'g-excluidas', r.id, jsonb_strip_nulls(jsonb_build_object('op', r.dados, 'excluidoEm', v_agora,
      'excluidoPor', jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome'), 'motivo', v_motivo,
      'conjunto', case when cardinality(v_ids) > 1 then to_jsonb(v_ids) end)))
    on conflict (modulo, caminho, id) do update set dados = excluded.dados, atualizado_em = now();
  end loop;
  delete from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = any(v_ids);

  -- lote que ficou sem nenhum lançamento sai do cadastro (assim a entrada pode ser refeita com a fabricação certa)
  if v_lotes is not null then
    delete from public.modulo_docs lt
     where lt.modulo = 'garrafoes' and lt.caminho = 'g-lotes' and lt.id = any(v_lotes)
       and not exists (select 1 from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
                        where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and l ->> 'lote' = lt.id);
  end if;
  return jsonb_build_object('excluidas', to_jsonb(v_ids));
end $$;
revoke execute on function public.garrafoes_excluir(text, text, boolean) from public, anon;
grant execute on function public.garrafoes_excluir(text, text, boolean) to authenticated;

-- ---------------------------------------------------------------- perfis (a gestão escolhe)
-- acessos que abrem o módulo (equipe e setor), com "Gerencia" (gestão) ou o perfil escolhido
create or replace function public.garrafoes_acessos()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_out jsonb;
begin
  if public.garrafoes_perfil_0056() <> 'gestao' then raise exception 'Só a gestão do módulo vê e muda os perfis.'; end if;
  with eq as (select modulos from public.acesso_senhas where ref = 'equipe' limit 1),
  pf as (select coalesce(dados -> 'refs', '{}'::jsonb) as refs from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-perfis' and id = 'perfis'),
  a as (
    select s.ref, s.nome, s.papel,
           case when s.ref like 'escritorio:%' and not ('abas' = any(s.modulos)) then s.modulos || coalesce((select modulos from eq), '{}') else s.modulos end as mods
      from public.acesso_senhas s
     where s.papel in ('equipe', 'setor'))
  select coalesce(jsonb_agg(jsonb_build_object('ref', a.ref, 'nome', a.nome, 'papel', a.papel,
           'gerencia', 'garrafoes:gerir' = any(a.mods),
           'perfil', coalesce((select refs ->> a.ref from pf), 'consulta')) order by a.nome), '[]'::jsonb)
    into v_out
    from a where a.mods && array['garrafoes', 'garrafoes:gerir'];
  return v_out;
end $$;
revoke execute on function public.garrafoes_acessos() from public, anon;
grant execute on function public.garrafoes_acessos() to authenticated;

create or replace function public.garrafoes_perfil_definir(p_ref text, p_perfil text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_meta jsonb := coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb);
  v_atual jsonb;
begin
  if public.garrafoes_perfil_0056() <> 'gestao' then raise exception 'Só a gestão do módulo muda os perfis.'; end if;
  if p_perfil is null or p_perfil not in ('consulta', 'entradas', 'entregas') then raise exception 'Perfil inválido.'; end if;
  if not exists (select 1 from jsonb_array_elements(public.garrafoes_acessos()) x where x ->> 'ref' = p_ref) then
    raise exception 'Este acesso não abre o módulo Garrafões. Marque o módulo para ele em Cadastros › Acesso ao app.';
  end if;
  perform pg_advisory_xact_lock(hashtext('garrafoes:perfis'));
  select dados into v_atual from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-perfis' and id = 'perfis';
  v_atual := coalesce(v_atual, '{}'::jsonb);
  v_atual := v_atual || jsonb_build_object('refs', coalesce(v_atual -> 'refs', '{}'::jsonb) || jsonb_build_object(p_ref, p_perfil),
    'atualizadoEm', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'atualizadoPor', jsonb_strip_nulls(jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome')));
  insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-perfis', 'perfis', v_atual)
  on conflict (modulo, caminho, id) do update set dados = excluded.dados, atualizado_em = now();
  return v_atual;
end $$;
revoke execute on function public.garrafoes_perfil_definir(text, text) from public, anon;
grant execute on function public.garrafoes_perfil_definir(text, text) to authenticated;

-- ---------------------------------------------------------------- gravação direta bloqueada
-- No módulo Garrafões só se grava pelas funções acima; direto, só o config/geral pela gestão. Nada se apaga direto
-- (os lançamentos do controle anterior ficam guardados como estão).
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'garrafoes_insere_0056') then
    create policy "garrafoes_insere_0056" on public.modulo_docs as restrictive for insert to authenticated
      with check (modulo <> 'garrafoes' or (caminho = 'config' and public.garrafoes_perfil_0056() = 'gestao'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'garrafoes_altera_0056') then
    create policy "garrafoes_altera_0056" on public.modulo_docs as restrictive for update to authenticated
      using (modulo <> 'garrafoes' or (caminho = 'config' and public.garrafoes_perfil_0056() = 'gestao'))
      with check (modulo <> 'garrafoes' or (caminho = 'config' and public.garrafoes_perfil_0056() = 'gestao'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'garrafoes_apaga_0056') then
    create policy "garrafoes_apaga_0056" on public.modulo_docs as restrictive for delete to authenticated
      using (modulo <> 'garrafoes');
  end if;
end $$;
