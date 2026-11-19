-- LEVÍSSIMA · 0057: Garrafões, segunda versão (pedido de 19/11/2026; substitui as regras de lote e sucata da 0056).
--
-- * Lote dos novos = fabricação (mês/ano). Saldo de novos por modelo + marca + fabricação; entradas da mesma
--   combinação somam no mesmo lote. Sem código de lote e sem cadastro de lote (g-lotes deixa de ser usado).
-- * Marcas por modelo: 20 L e 10 L = AGS e Montico; 20 L com rosca = Montico e Angioplast.
-- * Sucata só por litragem (20 L e 10 L), sem marca, lote, fabricação ou validade. Não há sucata de 20 L com rosca.
--   Os motivos ficam registrados na entrada (troca), sem dividir o estoque.
-- * 20 L com rosca: só entrada de novos, saída/venda e contagem de novos (sem troca, retirada ou contagem de sucata).
-- * Saída / Venda e troca exigem cliente e a assinatura do cliente na tela (imagem PNG + o resumo exato que ele
--   assinou), gravadas em g-assin/<id da operação> junto com a operação, numa transação só.
-- * Entrada de novos exige a foto da nota tirada na hora (JPEG), gravada em g-fotos/<id da operação> na mesma
--   transação: se a imagem não grava, a entrada não acontece.
-- * Retirada: quem recolheu (AGS, Montico ou outro nome) e a quantidade; baixa o saldo único da sucata da litragem.
-- * Continua da 0056: perfis, trava por modelo, saldo conferido de novo ao gravar, sem saldo negativo, idempotência pelo
--   id e pela origem, exclusão só pela gestão (com conjunto retirada + recebimentos e auditoria em g-excluidas) e
--   gravação direta bloqueada (as políticas da 0056 também cobrem g-assin e g-fotos).
-- * Em 19/11/2026 não havia nenhuma operação no formato da 0056 (g-ops vazio), então nada precisa ser convertido.

-- ---------------------------------------------------------------- auxiliares
create or replace function public.garrafoes_marca_ok_0057(p_modelo text, p_marca text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_modelo when '20LR' then p_marca in ('Montico', 'Angioplast') when '20L' then p_marca in ('AGS', 'Montico')
                       when '10L' then p_marca in ('AGS', 'Montico') else false end;
$$;
revoke execute on function public.garrafoes_marca_ok_0057(text, text) from public, anon, authenticated;

create or replace function public.garrafoes_marcas_txt_0057(p_modelo text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select case p_modelo when '20LR' then 'Montico ou Angioplast' else 'AGS ou Montico' end; $$;
revoke execute on function public.garrafoes_marcas_txt_0057(text) from public, anon, authenticated;

-- saldo de cada chave do modelo: 'N|<marca>|<fabricação>' para novos, 'S' para a sucata; sem as operações p_sem
create or replace function public.garrafoes_saldos_0057(p_modelo text, p_sem text[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(k, s), '{}'::jsonb) from (
    select case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'marca') || '|' || (l ->> 'fabricacao') else 'S' end as k,
           sum((l ->> 'qtd')::bigint) as s
      from public.modulo_docs d
     cross join lateral jsonb_array_elements(case when jsonb_typeof(d.dados -> 'linhas') = 'array' then d.dados -> 'linhas' else '[]'::jsonb end) l
     where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.dados ->> 'modelo' = p_modelo
       and not (d.id = any(coalesce(p_sem, '{}')))
     group by 1) x;
$$;
revoke execute on function public.garrafoes_saldos_0057(text, text[]) from public, anon, authenticated;

create or replace function public.garrafoes_nome_chave_0057(p_chave text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when p_chave = 'S' then 'a sucata'
              else 'os novos ' || split_part(p_chave, '|', 2) || ' fabricação ' || public.garrafoes_mes_0056(split_part(p_chave, '|', 3)) end;
$$;
revoke execute on function public.garrafoes_nome_chave_0057(text) from public, anon, authenticated;

-- fabricação válida para a data da movimentação ('AAAA-MM', de 2015 até o mês da data)
create or replace function public.garrafoes_fab_0057(p_fab text, p_data date)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  if p_fab is null or p_fab !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Informe o mês e o ano de fabricação.'; end if;
  if p_fab < '2015-01' then raise exception 'Fabricação muito antiga (%). Confira o mês e o ano.', public.garrafoes_mes_0056(p_fab); end if;
  if p_fab > to_char(p_data, 'YYYY-MM') then
    raise exception 'A fabricação (%) não pode ser depois da data da movimentação.', public.garrafoes_mes_0056(p_fab);
  end if;
  return p_fab;
end $$;
revoke execute on function public.garrafoes_fab_0057(text, date) from public, anon, authenticated;

-- linhas de novos que SAEM (venda ou troca): marca do modelo, fabricação, quantidade; junta a mesma fabricação e
-- confere o saldo. Devolve as linhas prontas para gravar (quantidade negativa).
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
    if v_fab is null or v_fab !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Escolha a fabricação de cada linha de novos.'; end if;
    v_qtd := public.garrafoes_int_0056(l -> 'qtd');
    if v_qtd is null or v_qtd < 1 then raise exception 'Informe a quantidade de novos de cada fabricação (número inteiro maior que zero).'; end if;
    k := 'N|' || (l ->> 'marca') || '|' || v_fab;
    v_pedido := v_pedido || jsonb_build_object(k, coalesce((v_pedido ->> k)::bigint, 0) + v_qtd);
  end loop;
  for k in select jsonb_object_keys(v_pedido) loop
    v_s := coalesce((v_saldos ->> k)::bigint, 0);
    v_p := (v_pedido ->> k)::bigint;
    if v_p > v_s then
      raise exception 'Os novos % da fabricação % têm % unidade(s) disponível(is); foram pedidas %.',
        split_part(k, '|', 2), public.garrafoes_mes_0056(split_part(k, '|', 3)), v_s, v_p;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('classe', 'novo', 'marca', split_part(k, '|', 2), 'fabricacao', split_part(k, '|', 3), 'qtd', -v_p));
  end loop;
  return v_out;
end $$;
revoke execute on function public.garrafoes_novos_saindo_0057(text, jsonb, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- registrar uma operação
-- p: { id: 'op-…' (gerado ao abrir o formulário), tipo, modelo, data 'AAAA-MM-DD', obs?, origem?, linhas: [...], … }
--   entrada:  linhas [{marca, fabricacao 'AAAA-MM', qtd}] (uma linha), foto 'data:image/jpeg;base64,…', vinculo? (retirada)
--   saida:    cliente, linhas [{marca, fabricacao, qtd}] (uma marca, uma ou mais fabricações), assinatura {imagem PNG, resumo}
--   troca:    cliente, totalSucata, linhas [{classe 'sucata', motivo, motivoDesc?, qtd}, {classe 'novo', marca, fabricacao, qtd}],
--             assinatura {imagem PNG, resumo}            (só 20 L e 10 L)
--   retirada: recolhidoPor, contrapartida ('novos' | 'sem'), qtd   (só 20 L e 10 L)
--   contagem: alvo ('novos' | 'sucata'), justificativa, linhas [{marca, fabricacao, registrado, contado}] ou [{registrado, contado}]
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
    if jsonb_array_length(p -> 'linhas') <> 1 then raise exception 'A entrada é de uma marca e uma fabricação por vez.'; end if;
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
      if v_k = any(v_vistas) then raise exception 'A mesma marca e fabricação aparecem duas vezes na contagem.'; end if;
      v_vistas := v_vistas || v_k;
      v_atual := coalesce((v_saldos ->> v_k)::bigint, 0);
      if v_atual <> v_reg then
        raise exception 'O saldo % mudou para % enquanto você contava (outro registro foi feito). Abra a contagem de novo.',
          case when v_k = 'S' then 'da sucata' else 'dos novos ' || (l ->> 'marca') || ' fabricação ' || public.garrafoes_mes_0056(v_fab) end, v_atual;
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

-- ---------------------------------------------------------------- excluir (só a gestão), com as chaves novas
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

  v_saldos := public.garrafoes_saldos_0057(v_modelo, v_ids);
  for k in
    select distinct case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'marca') || '|' || (l ->> 'fabricacao') else 'S' end
      from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
     where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.id = any(v_ids)
  loop
    v_s := coalesce((v_saldos ->> k)::bigint, 0);
    if v_s < 0 then
      select string_agg(x.txt, '; ') into v_dep from (
        select (case d.dados ->> 'tipo' when 'saida' then 'venda para ' || coalesce(d.dados ->> 'cliente', 'cliente')
                  when 'troca' then 'troca com ' || coalesce(d.dados ->> 'cliente', 'cliente')
                  when 'retirada' then 'retirada' when 'contagem' then 'contagem' else d.dados ->> 'tipo' end)
               || ' de ' || to_char((d.dados ->> 'data')::date, 'DD/MM/YYYY') || ' (' || abs((l ->> 'qtd')::bigint) || ')' as txt
          from public.modulo_docs d cross join lateral jsonb_array_elements(d.dados -> 'linhas') l
         where d.modulo = 'garrafoes' and d.caminho = 'g-ops' and d.dados ->> 'modelo' = v_modelo and not (d.id = any(v_ids))
           and (l ->> 'qtd')::bigint < 0
           and case when l ->> 'classe' = 'novo' then 'N|' || (l ->> 'marca') || '|' || (l ->> 'fabricacao') else 'S' end = k
         order by d.dados ->> 'data' desc, d.dados ->> 'registradoEm' desc
         limit 5) x;
      raise exception 'Excluir deixaria % com saldo %. Exclua ou corrija antes: %.', public.garrafoes_nome_chave_0057(k), v_s, coalesce(v_dep, 'os lançamentos que usaram esse saldo');
    end if;
  end loop;

  for r in select id, dados from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = any(v_ids) loop
    insert into public.modulo_docs (modulo, caminho, id, dados)
    values ('garrafoes', 'g-excluidas', r.id, jsonb_strip_nulls(jsonb_build_object('op', r.dados, 'excluidoEm', v_agora,
      'excluidoPor', jsonb_build_object('ref', v_meta ->> 'ref', 'nome', v_meta ->> 'nome'), 'motivo', v_motivo,
      'conjunto', case when cardinality(v_ids) > 1 then to_jsonb(v_ids) end)))
    on conflict (modulo, caminho, id) do update set dados = excluded.dados, atualizado_em = now();
  end loop;
  -- a assinatura e a foto da nota ficam guardadas (g-assin, g-fotos): a exclusão só tira a operação do saldo
  delete from public.modulo_docs where modulo = 'garrafoes' and caminho = 'g-ops' and id = any(v_ids);
  return jsonb_build_object('excluidas', to_jsonb(v_ids));
end $$;
revoke execute on function public.garrafoes_excluir(text, text, boolean) from public, anon;
grant execute on function public.garrafoes_excluir(text, text, boolean) to authenticated;
