-- LEVÍSSIMA · 0060: Garrafões — "fabricação" passa a se chamar "lote" e o lote vai até o mês seguinte ao atual
-- (pedido de 19/11/2026, tarde).
--
-- * O lote dos novos continua sendo o mês/ano (campo "fabricacao" nos dados, sem mudança de formato nem de saldo) e a
--   validade continua 3 anos depois do lote. Só os textos das mensagens trocam "fabricação" por "lote".
-- * O lote não depende mais da data da movimentação: vale qualquer mês de 01/2015 até o mês seguinte ao atual
--   (fuso America/Sao_Paulo), na entrada e no "lote encontrado" da contagem.
-- * Refaz, com os mesmos nomes e parâmetros: garrafoes_fab_0057, garrafoes_nome_chave_0057, garrafoes_novos_saindo_0057
--   e garrafoes_registrar (só os textos; a regra das operações é a da 0057).

create or replace function public.garrafoes_fab_0057(p_fab text, p_data date)
returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_max text := to_char(date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date) + interval '1 month', 'YYYY-MM');
begin
  -- 19/11/2026: o lote (mês/ano) não depende mais da data da movimentação: de 01/2015 até o mês seguinte ao atual
  if p_fab is null or p_fab !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Informe o mês e o ano do lote.'; end if;
  if p_fab < '2015-01' then raise exception 'Lote muito antigo (%). Confira o mês e o ano.', public.garrafoes_mes_0056(p_fab); end if;
  if p_fab > v_max then
    raise exception 'O lote (%) pode ser no máximo um mês depois do mês atual (até %).', public.garrafoes_mes_0056(p_fab), public.garrafoes_mes_0056(v_max);
  end if;
  return p_fab;
end $$;
revoke execute on function public.garrafoes_fab_0057(text, date) from public, anon, authenticated;

create or replace function public.garrafoes_nome_chave_0057(p_chave text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when p_chave = 'S' then 'a sucata'
              else 'os novos ' || split_part(p_chave, '|', 2) || ' lote ' || public.garrafoes_mes_0056(split_part(p_chave, '|', 3)) end;
$$;
revoke execute on function public.garrafoes_nome_chave_0057(text) from public, anon, authenticated;

create or replace function public.garrafoes_novos_saindo_0057(p_modelo text, p_linhas jsonb, p_mesma_marca boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  l jsonb; v_marca text := null; v_fab text; v_qtd integer; k text;
  v_pedido jsonb := '{}'::jsonb;
  v_saldos jsonb := public.garrafoes_saldos_0057(p_modelo);
  v_out jsonb := '[]'::jsonb;
  v_s bigint; v_p bigint;
begin
  for l in select * from jsonb_array_elements(p_linhas) loop
    if not public.garrafoes_marca_ok_0057(p_modelo, l ->> 'marca') then
      raise exception 'Escolha a marca dos novos: % para este modelo.', public.garrafoes_marcas_txt_0057(p_modelo);
    end if;
    if p_mesma_marca then
      if v_marca is null then v_marca := l ->> 'marca';
      elsif v_marca <> l ->> 'marca' then raise exception 'A venda é de uma marca por vez. Registre a outra marca em outra venda.';
      end if;
    end if;
    v_fab := l ->> 'fabricacao';
    if v_fab is null or v_fab !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Escolha o lote de cada linha de novos.'; end if;
    v_qtd := public.garrafoes_int_0056(l -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de novos de cada lote (número inteiro maior que zero).'; end if;
    k := 'N|' || (l ->> 'marca') || '|' || v_fab;
    v_pedido := v_pedido || jsonb_build_object(k, coalesce((v_pedido ->> k)::bigint, 0) + v_qtd);
  end loop;
  for k in select jsonb_object_keys(v_pedido) loop
    v_s := coalesce((v_saldos ->> k)::bigint, 0);
    v_p := (v_pedido ->> k)::bigint;
    if v_p > v_s then
      raise exception 'Os novos % do lote % têm % unidade(s) disponível(is); foram pedidas %.',
        split_part(k, '|', 2), public.garrafoes_mes_0056(split_part(k, '|', 3)), v_s, v_p;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', split_part(k, '|', 2), 'fabricacao', split_part(k, '|', 3), 'qtd', -v_p));
  end loop;
  return v_out;
end $$;
revoke execute on function public.garrafoes_novos_saindo_0057(text, jsonb, boolean) from public, anon, authenticated;

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
  v_agora text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_por jsonb := jsonb_strip_nulls(jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome', 'papel', v_meta ->> 'papel'));
  v_data date;
  v_doc jsonb;
  v_linhas jsonb := '[]'::jsonb;
  v_saldos jsonb;
  l jsonb;
  v_fab text; v_qtd integer; v_motivo text; v_desc text;
  v_obs text := nullif(left(btrim(coalesce(p ->> 'obs', '')), 500), '');
  v_cli text; v_rec text; v_contra text; v_vinc text; v_vdoc jsonb; v_just text; v_alvo text;
  v_suc jsonb := '{}'::jsonb; v_sinfo jsonb := '{}'::jsonb;
  v_tot integer := 0; v_tot_inf integer;
  v_nov jsonb := '[]'::jsonb;
  v_reg integer; v_cont integer; v_atual bigint; v_dif boolean := false;
  v_vistas text[] := '{}'; v_k text;
  v_origem jsonb := null;
  v_ass_img text; v_ass_res text; v_foto text;
  k text;
begin
  if v_perfil = '' then raise exception 'Sem acesso ao módulo Garrafões.'; end if;
  if v_id is null or v_id !~ '^op-[A-Za-z0-9]{12,40}$' then raise exception 'Identificador da operação inválido. Abra o formulário de novo.'; end if;
  if v_modelo is null or v_modelo not in ('20L', '20LR', '10L') then raise exception 'Modelo inválido.'; end if;
  if v_tipo is null or v_tipo not in ('entrada', 'saida', 'troca', 'retirada', 'contagem') then raise exception 'Tipo de operação inválido.'; end if;
  if v_modelo = '20LR' and (v_tipo in ('troca', 'retirada') or (v_tipo = 'contagem' and p ->> 'alvo' = 'sucata')) then
    raise exception 'O 20 L com rosca não tem troca nem sucata: só entrada, venda e contagem de novos.';
  end if;
  if v_tipo in ('entrada', 'contagem') and v_perfil not in ('entradas', 'gestao') then
    raise exception 'Seu perfil não registra %. Fale com a gestão do módulo.', case v_tipo when 'entrada' then 'entradas de novos' else 'contagens físicas' end;
  end if;
  if v_tipo in ('saida', 'troca', 'retirada') and v_perfil not in ('entregas', 'gestao') then
    raise exception 'Seu perfil não registra %. Fale com a gestão do módulo.',
      case v_tipo when 'saida' then 'vendas de novos' when 'troca' then 'trocas com cliente' else 'retiradas de sucata' end;
  end if;
  if v_tipo <> 'retirada' and (jsonb_typeof(p -> 'linhas') <> 'array' or jsonb_array_length(p -> 'linhas') < 1) then raise exception 'Preencha ao menos uma linha.'; end if;
  if jsonb_typeof(p -> 'linhas') = 'array' and jsonb_array_length(p -> 'linhas') > 40 then raise exception 'Linhas demais numa operação só.'; end if;

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

  -- assinatura do cliente (venda e troca): imagem desenhada na tela + o resumo exato que ele assinou
  if v_tipo in ('saida', 'troca') then
    v_cli := nullif(left(btrim(coalesce(p ->> 'cliente', '')), 120), '');
    if v_cli is null then raise exception 'Informe o cliente.'; end if;
    v_ass_img := p -> 'assinatura' ->> 'imagem';
    v_ass_res := nullif(left(btrim(coalesce(p -> 'assinatura' ->> 'resumo', '')), 4000), '');
    if v_ass_img is null or v_ass_img !~ '^data:image/png;base64,[A-Za-z0-9+/=]+$' or length(v_ass_img) < 1500 or length(v_ass_img) > 600000 then
      raise exception 'Falta a assinatura do cliente (feita na tela). Peça para o cliente assinar.';
    end if;
    if v_ass_res is null then raise exception 'Falta o resumo que o cliente assinou. Revise e peça a assinatura de novo.'; end if;
  end if;

  if v_tipo = 'entrada' then
    if jsonb_array_length(p -> 'linhas') <> 1 then raise exception 'A entrada é de uma marca e um lote por vez.'; end if;
    l := p -> 'linhas' -> 0;
    if not public.garrafoes_marca_ok_0057(v_modelo, l ->> 'marca') then
      raise exception 'Escolha a marca: % para este modelo.', public.garrafoes_marcas_txt_0057(v_modelo);
    end if;
    v_fab := public.garrafoes_fab_0057(l ->> 'fabricacao', v_data);
    v_qtd := public.garrafoes_int_0056(l -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade em unidades (número inteiro maior que zero).'; end if;
    v_foto := p ->> 'foto';
    if v_foto is null or v_foto !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(v_foto) < 5000 then
      raise exception 'Falta a foto da nota do recebimento. Tire a foto da nota antes de concluir.';
    end if;
    if length(v_foto) > 3000000 then raise exception 'A foto da nota ficou grande demais. Tire de novo.'; end if;
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
    v_linhas := jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', l ->> 'marca', 'fabricacao', v_fab, 'qtd', v_qtd));

  elsif v_tipo = 'saida' then
    v_linhas := public.garrafoes_novos_saindo_0057(v_modelo, p -> 'linhas', true);

  elsif v_tipo = 'troca' then
    for l in select * from jsonb_array_elements(p -> 'linhas') loop
      if l ->> 'classe' = 'sucata' then
        v_motivo := l ->> 'motivo';
        if v_motivo is null or v_motivo not in ('Quebrado ou trincado', 'Vencido', 'Vazamento', 'Contaminado ou sujo', 'Outro') then
          raise exception 'Escolha o motivo de cada linha de sucata.';
        end if;
        v_desc := nullif(left(btrim(coalesce(l ->> 'motivoDesc', '')), 120), '');
        if v_motivo = 'Outro' and (v_desc is null or length(v_desc) < 3) then raise exception 'Descreva o motivo "Outro" da sucata.'; end if;
        if v_motivo <> 'Outro' then v_desc := null; end if;
        v_qtd := public.garrafoes_int_0056(l -> 'qtd');
        if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de cada motivo (número inteiro maior que zero).'; end if;
        v_k := v_motivo || '|' || coalesce(lower(v_desc), '');
        v_suc := v_suc || jsonb_build_object(v_k, coalesce((v_suc ->> v_k)::integer, 0) + v_qtd);
        v_sinfo := v_sinfo || jsonb_build_object(v_k, jsonb_strip_nulls(jsonb_build_object('motivo', v_motivo, 'motivoDesc', v_desc)));
        v_tot := v_tot + v_qtd;
      elsif l ->> 'classe' = 'novo' then
        v_nov := v_nov || jsonb_build_array(l);
      else
        raise exception 'Linha da troca sem tipo (sucata ou novo).';
      end if;
    end loop;
    if v_tot = 0 then raise exception 'Informe as sucatas recebidas do cliente.'; end if;
    if jsonb_array_length(v_nov) = 0 then raise exception 'Informe os novos entregues ao cliente.'; end if;
    v_tot_inf := public.garrafoes_int_0056(p -> 'totalSucata');
    if v_tot_inf is null or v_tot_inf <> v_tot then
      raise exception 'A soma dos motivos (%) não bate com o total de sucatas recebidas (%).', v_tot, coalesce(p ->> 'totalSucata', '?');
    end if;
    for k in select jsonb_object_keys(v_suc) loop
      v_linhas := v_linhas || jsonb_build_array((v_sinfo -> k) || jsonb_build_object('classe', 'sucata', 'qtd', (v_suc ->> k)::integer));
    end loop;
    v_linhas := v_linhas || public.garrafoes_novos_saindo_0057(v_modelo, v_nov, false);

  elsif v_tipo = 'retirada' then
    v_rec := nullif(left(btrim(coalesce(p ->> 'recolhidoPor', '')), 80), '');
    if v_rec is null or length(v_rec) < 2 then raise exception 'Informe quem recolheu a sucata.'; end if;
    v_contra := p ->> 'contrapartida';
    if v_contra is null or v_contra not in ('novos', 'sem') then raise exception 'Informe se quem recolheu vai entregar novos em troca desta sucata.'; end if;
    v_qtd := public.garrafoes_int_0056(p -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de sucata retirada (número inteiro maior que zero).'; end if;
    v_atual := coalesce((public.garrafoes_saldos_0057(v_modelo) ->> 'S')::bigint, 0);
    if v_qtd > v_atual then raise exception 'A sucata tem % unidade(s) em estoque; a retirada informa %.', v_atual, v_qtd; end if;
    v_linhas := jsonb_build_array(jsonb_build_object('classe', 'sucata', 'qtd', -v_qtd));

  elsif v_tipo = 'contagem' then
    v_alvo := p ->> 'alvo';
    if v_alvo is null or v_alvo not in ('novos', 'sucata') then raise exception 'Escolha o que foi contado: novos ou sucata.'; end if;
    v_just := nullif(left(btrim(coalesce(p ->> 'justificativa', '')), 500), '');
    v_saldos := public.garrafoes_saldos_0057(v_modelo);
    for l in select * from jsonb_array_elements(p -> 'linhas') loop
      v_cont := public.garrafoes_int_0056(l -> 'contado');
      if v_cont is null then raise exception 'Informe a quantidade contada (zero se não houver nenhum).'; end if;
      v_reg := coalesce(public.garrafoes_int_0056(l -> 'registrado'), 0);
      if v_alvo = 'novos' then
        if not public.garrafoes_marca_ok_0057(v_modelo, l ->> 'marca') then
          raise exception 'Marca inválida na contagem: % para este modelo.', public.garrafoes_marcas_txt_0057(v_modelo);
        end if;
        v_fab := public.garrafoes_fab_0057(l ->> 'fabricacao', v_data);
        v_k := 'N|' || (l ->> 'marca') || '|' || v_fab;
      else
        if jsonb_array_length(p -> 'linhas') <> 1 then raise exception 'A contagem de sucata tem um número só (o total da litragem).'; end if;
        v_k := 'S';
      end if;
      if v_k = any(v_vistas) then raise exception 'A mesma marca e lote aparecem duas vezes na contagem.'; end if;
      v_vistas := v_vistas || v_k;
      v_atual := coalesce((v_saldos ->> v_k)::bigint, 0);
      if v_atual <> v_reg then
        raise exception 'O saldo % mudou para % enquanto você contava (outro registro foi feito). Abra a contagem de novo.',
          case when v_k = 'S' then 'da sucata' else 'dos novos ' || (l ->> 'marca') || ' lote ' || public.garrafoes_mes_0056(v_fab) end, v_atual;
      end if;
      if v_cont <> v_atual then v_dif := true; end if;
      if v_alvo = 'novos' then
        v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', l ->> 'marca', 'fabricacao', v_fab,
          'registrado', v_atual, 'contado', v_cont, 'qtd', v_cont - v_atual));
      else
        v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('classe', 'sucata', 'registrado', v_atual, 'contado', v_cont, 'qtd', v_cont - v_atual));
      end if;
    end loop;
    if v_dif and (v_just is null or length(v_just) < 3) then raise exception 'Explique na justificativa por que a contagem deu diferente do registrado.'; end if;
  end if;

  v_doc := jsonb_strip_nulls(jsonb_build_object(
    'tipo', v_tipo, 'modelo', v_modelo, 'data', to_char(v_data, 'YYYY-MM-DD'), 'registradoEm', v_agora,
    'por', v_por, 'perfil', v_perfil, 'cliente', v_cli, 'recolhidoPor', v_rec, 'contrapartida', v_contra, 'vinculo', v_vinc,
    'alvo', v_alvo, 'justificativa', v_just, 'obs', v_obs, 'origem', v_origem,
    'assinada', case when v_ass_img is not null then true end, 'fotoNota', case when v_foto is not null then true end,
    'linhas', v_linhas));
  insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-ops', v_id, v_doc);
  -- a assinatura e a foto ficam fora da operação (a lista de operações carrega leve), na mesma transação
  if v_ass_img is not null then
    insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-assin', v_id,
      jsonb_build_object('imagem', v_ass_img, 'resumo', v_ass_res, 'cliente', v_cli, 'tipo', v_tipo, 'modelo', v_modelo,
        'data', to_char(v_data, 'YYYY-MM-DD'), 'em', v_agora, 'por', v_por,
        'aviso', 'Assinatura manuscrita feita na tela do aparelho (não é assinatura com certificado digital).'));
  end if;
  if v_foto is not null then
    insert into public.modulo_docs (modulo, caminho, id, dados) values ('garrafoes', 'g-fotos', v_id,
      jsonb_build_object('imagem', v_foto, 'tipo', 'nota', 'modelo', v_modelo, 'data', to_char(v_data, 'YYYY-MM-DD'), 'em', v_agora, 'por', v_por));
  end if;
  return v_doc || jsonb_build_object('id', v_id);
end $$;
revoke execute on function public.garrafoes_registrar(jsonb) from public, anon;
grant execute on function public.garrafoes_registrar(jsonb) to authenticated;
