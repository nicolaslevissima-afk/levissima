-- LEVÍSSIMA · 0054: tablets das máquinas (pedido de 17/11/2026, parte 2 do pedido da Laura/PCP).
--
-- * Cada máquina da configuração das linhas (mp-config/linhas-producao) tem um id e um acesso próprio
--   ('setor:maq-<id>', gravados pela 0055): a senha de setor ligada a esse acesso abre direto a tela da máquina.
-- * O tablet não lê nem grava as coleções pela API: só pelas funções abaixo (SECURITY DEFINER), que conferem que o
--   acesso é de uma máquina e gravam sempre na máquina e na linha dele (nunca em outra).
-- * Operador: identificado pela senha de 4 números (pin_conferir) e guardado em maq_sessoes; cada lançamento leva o
--   operador que estava identificado no tablet naquela hora (troca de operador preserva a autoria).
-- * OP vigente: a OP em execução na linha naquele horário (iniciar/retomar/pausar do PCP em producao-eventos). O
--   lançamento retroativo vai para a OP daquele horário. Troca de OP dentro do horário: o tablet lança um registro
--   por trecho (maq_segmentos); a função recusa um registro que atravessa a troca. Sem OP: o registro fica sem OP,
--   para o PCP vincular, e não mexe em estoque nem em saldo de OP.
-- * Etapa final da linha (máquina com "producao" = entra no estoque): depois que o PCP liga o apontamento pelas
--   máquinas na linha (apontaMaquinas.desde), o lançamento dela vira uma entrada estimada no estoque (origem
--   'maquina', pendente), que abate da OP e entra no estoque quando o PCP confirma, como o lançamento da hora. As
--   outras máquinas só alimentam os indicadores. Lançamento duplicado não entra no estoque até o PCP resolver.
-- * Paradas por máquina (início, fim, motivo, observação, só a máquina ou a linha toda), sem sobreposição; não mudam
--   a situação da OP.
-- * Idempotência: o tablet manda um id por lançamento; o mesmo id de novo devolve o registro que já existe.
-- * Conferência (PCP e liderança): maq_painel lê; maq_corrigir e maq_validar só a senha mestre e quem tem
--   "Configura o PCP", "Confirma a produção" ou "Vê e corrige lançamentos"; correção guarda o histórico.
-- * Iniciar, pausar e retomar a OP (producao-eventos) e concluir a OP (producao-ordens) passam a ser só da senha
--   mestre e de quem tem "Configura o PCP" também no banco.
-- * "Configura o PCP" também muda a unidade, o modo de contagem e a etapa final das máquinas e liga o apontamento
--   pelas máquinas; incluir ou tirar máquina e mudar nome ou acesso continuam só da senha mestre.

-- ---------------------------------------------------------------- coleção dos registros das máquinas
create or replace function public.colecao_producao(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('producao-ordens', 'producao-eventos', 'mp-insumos', 'mp-fichas', 'mp-movs', 'garrafoes-fechamentos', 'mp-config', 'producao-maq'); $$;

create index if not exists docs_maq_0054 on public.docs ((data ->> 'maquinaId'), (data ->> 'ini')) where colecao = 'producao-maq';
create index if not exists docs_maq_dia_0054 on public.docs ((data ->> 'dia')) where colecao = 'producao-maq';
create index if not exists docs_eventos_linha_0054 on public.docs ((data ->> 'linha')) where colecao = 'producao-eventos';

-- ---------------------------------------------------------------- ajudantes
create or replace function public.maq_ts_0054(p text)
returns timestamptz
language plpgsql
immutable
set search_path = public, pg_temp
as $$ begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  return p::timestamptz;
exception when others then return null;
end $$;
revoke execute on function public.maq_ts_0054(text) from public, anon, authenticated;

create or replace function public.maq_num_0054(p text)
returns numeric
language plpgsql
immutable
set search_path = public, pg_temp
as $$ begin
  if p is null or btrim(p) !~ '^-?\d+(\.\d+)?$' then return null; end if;
  return btrim(p)::numeric;
end $$;
revoke execute on function public.maq_num_0054(text) from public, anon, authenticated;

create or replace function public.maq_iso_0054(p timestamptz)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select to_char(p at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'); $$;
revoke execute on function public.maq_iso_0054(timestamptz) from public, anon, authenticated;

-- a máquina e a linha do acesso que está usando o app (null se não for o tablet de uma máquina)
create or replace function public.maq_minha_0054()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object('linha', l - 'maquinas', 'maquina', m)
    from public.docs d,
         jsonb_array_elements(case when jsonb_typeof(d.data -> 'linhas') = 'array' then d.data -> 'linhas' else '[]'::jsonb end) l,
         jsonb_array_elements(case when jsonb_typeof(l -> 'maquinas') = 'array' then l -> 'maquinas' else '[]'::jsonb end) m
   where d.colecao = 'mp-config' and d.id = 'linhas-producao'
     and coalesce(public.papel_atual(), '') = 'setor'
     and coalesce(m ->> 'acesso', '') <> '' and m ->> 'acesso' = public.ref_atual()
   limit 1;
$$;
revoke execute on function public.maq_minha_0054() from public, anon, authenticated;

-- a OP em execução na linha num horário (pelo iniciar/retomar/pausar do PCP)
create or replace function public.maq_op_em_0054(p_linha text, p_t timestamptz)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select e.op from (
    select distinct on (d.data ->> 'opId') d.data ->> 'opId' as op, d.data ->> 'tipo' as tipo, public.maq_ts_0054(d.data ->> 'em') as em
      from public.docs d
     where d.colecao = 'producao-eventos' and d.data ->> 'linha' = p_linha
       and d.data ->> 'tipo' in ('iniciar', 'retomar', 'pausar') and coalesce(d.data ->> 'opId', '') <> ''
       and public.maq_ts_0054(d.data ->> 'em') <= p_t
     order by d.data ->> 'opId', public.maq_ts_0054(d.data ->> 'em') desc
  ) e
  join public.docs o on o.colecao = 'producao-ordens' and o.id = e.op
  where e.tipo in ('iniciar', 'retomar')
    and not (coalesce(o.data ->> 'status', '') = 'concluida' and coalesce(public.maq_ts_0054(o.data ->> 'concluidoEm'), '-infinity'::timestamptz) <= p_t)
  order by e.em desc
  limit 1;
$$;
revoke execute on function public.maq_op_em_0054(text, timestamptz) from public, anon, authenticated;

-- o que o tablet precisa saber da OP (número, produtos, unidade, paletização)
create or replace function public.maq_op_info_0054(p_op text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object('id', o.id, 'numero', o.data -> 'numero', 'status', o.data ->> 'status', 'obs', coalesce(o.data ->> 'obs', ''),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('produtoId', it ->> 'produtoId', 'nome', coalesce(p.data ->> 'nome', it ->> 'produtoNome', ''),
                         'unidade', coalesce(nullif(it ->> 'unidade', ''), p.data ->> 'unidade', 'unidades'), 'quantidade', public.maq_num_0054(it ->> 'quantidade'),
                         'unidadesPorPalete', public.maq_num_0054(p.data ->> 'unidadesPorPalete')))
                         from jsonb_array_elements(case when jsonb_typeof(o.data -> 'itens') = 'array' then o.data -> 'itens' else '[]'::jsonb end) it
                         left join public.docs p on p.colecao = 'produtos' and p.id = it ->> 'produtoId'
                        where coalesce(public.maq_num_0054(it ->> 'quantidade'), 0) > 0), '[]'::jsonb))
    from public.docs o where o.colecao = 'producao-ordens' and o.id = p_op;
$$;
revoke execute on function public.maq_op_info_0054(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- operador do tablet
create table if not exists public.maq_sessoes (
  id bigserial primary key,
  acesso text not null,
  maquina text not null default '',
  membro text not null,
  nome text not null default '',
  desde timestamptz not null default now(),
  ate timestamptz
);
create index if not exists maq_sessoes_acesso on public.maq_sessoes (acesso, desde desc);
alter table public.maq_sessoes enable row level security;
revoke all on public.maq_sessoes from public, anon, authenticated;

create or replace function public.maq_operador_entrar(p_pin text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare v jsonb := public.maq_minha_0054(); r jsonb; v_nome text; v_ref text := public.ref_atual();
begin
  if v is null then raise exception 'maquina'; end if;
  r := public.pin_conferir(p_pin);
  if not coalesce((r ->> 'ok')::boolean, false) then return r; end if;
  select coalesce(data ->> 'nome', '') into v_nome from public.docs where colecao = 'equipe' and id = r ->> 'membro';
  update public.maq_sessoes set ate = now() where acesso = v_ref and ate is null;
  insert into public.maq_sessoes (acesso, maquina, membro, nome) values (v_ref, coalesce(v -> 'maquina' ->> 'id', ''), r ->> 'membro', coalesce(v_nome, ''));
  return jsonb_build_object('ok', true, 'membro', r ->> 'membro', 'nome', coalesce(v_nome, ''));
end $$;
revoke execute on function public.maq_operador_entrar(text) from public, anon;
grant execute on function public.maq_operador_entrar(text) to authenticated;

create or replace function public.maq_operador_sair()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  if public.maq_minha_0054() is null then raise exception 'maquina'; end if;
  update public.maq_sessoes set ate = now() where acesso = public.ref_atual() and ate is null;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.maq_operador_sair() from public, anon;
grant execute on function public.maq_operador_sair() to authenticated;

-- ---------------------------------------------------------------- tela do tablet
create or replace function public.maq_contexto()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v jsonb := public.maq_minha_0054(); v_l jsonb; v_m jsonb; v_ref text := public.ref_atual(); v_op text; v_oper jsonb; v_parada jsonb;
  v_ult jsonb; v_cont jsonb; v_pend jsonb := '[]'::jsonb; h int; v_base timestamptz; v_hi timestamptz; v_hf timestamptz;
begin
  if v is null then return jsonb_build_object('maquina', null); end if;
  v_l := v -> 'linha'; v_m := v -> 'maquina';
  select jsonb_build_object('membro', membro, 'nome', nome, 'desde', public.maq_iso_0054(desde)) into v_oper
    from public.maq_sessoes where acesso = v_ref and ate is null order by desde desc limit 1;
  v_op := public.maq_op_em_0054(v_l ->> 'id', now());
  select jsonb_build_object('id', id) || data into v_parada from public.docs
   where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'parada'
     and coalesce(data ->> 'fim', '') = '' and coalesce(data ->> 'estado', '') <> 'anulado'
   order by data ->> 'ini' desc limit 1;
  select coalesce(jsonb_agg(x order by x ->> 'enviadoEm' desc), '[]'::jsonb) into v_ult from (
    select jsonb_build_object('id', id) || (data - 'historico') as x from public.docs
     where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id'
     order by data ->> 'enviadoEm' desc limit 15) s;
  select jsonb_build_object('contador', data -> 'contador', 'fim', data ->> 'fim') into v_cont from public.docs
   where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'producao'
     and coalesce(data ->> 'estado', '') <> 'anulado' and jsonb_typeof(data -> 'contador') = 'number'
   order by data ->> 'fim' desc limit 1;
  -- horas sem lançamento: só as horas em que havia OP em execução na linha e a máquina não estava parada a hora toda
  v_base := date_trunc('hour', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
  for h in 1 .. 12 loop
    v_hi := v_base - make_interval(hours => h); v_hf := v_hi + interval '1 hour';
    continue when public.maq_op_em_0054(v_l ->> 'id', v_hi + interval '30 minutes') is null;
    continue when exists (select 1 from public.docs where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'producao'
                           and coalesce(data ->> 'estado', '') <> 'anulado' and public.maq_ts_0054(data ->> 'ini') < v_hf and public.maq_ts_0054(data ->> 'fim') > v_hi);
    continue when exists (select 1 from public.docs where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'parada'
                           and coalesce(data ->> 'estado', '') <> 'anulado' and public.maq_ts_0054(data ->> 'ini') <= v_hi
                           and coalesce(public.maq_ts_0054(data ->> 'fim'), 'infinity'::timestamptz) >= v_hf);
    v_pend := v_pend || jsonb_build_object('ini', public.maq_iso_0054(v_hi), 'fim', public.maq_iso_0054(v_hf));
  end loop;
  return jsonb_build_object('maquina', v_m, 'linha', v_l, 'operador', v_oper, 'op', case when v_op is null then null else public.maq_op_info_0054(v_op) end,
    'parada', v_parada, 'ultimos', v_ult, 'ultimoContador', v_cont, 'pendentes', v_pend, 'agora', public.maq_iso_0054(now()));
end $$;
revoke execute on function public.maq_contexto() from public, anon;
grant execute on function public.maq_contexto() to authenticated;

-- trechos de um horário com a OP de cada um (o PCP trocou a OP no meio: um trecho para cada OP)
create or replace function public.maq_segmentos(p_ini timestamptz, p_fim timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v jsonb := public.maq_minha_0054(); v_lid text; v_pts timestamptz[] := array[p_ini]; t timestamptz; v_out jsonb := '[]'::jsonb;
  i int; a timestamptz; b timestamptz; v_op text; v_ult text := null; n int;
begin
  if v is null then raise exception 'maquina'; end if;
  if p_ini is null or p_fim is null or p_fim <= p_ini or p_fim - p_ini > interval '4 hours' then raise exception 'intervalo'; end if;
  v_lid := v -> 'linha' ->> 'id';
  for t in select distinct public.maq_ts_0054(data ->> 'em') as em from public.docs
            where colecao = 'producao-eventos' and data ->> 'linha' = v_lid and data ->> 'tipo' in ('iniciar', 'retomar', 'pausar')
              and public.maq_ts_0054(data ->> 'em') > p_ini and public.maq_ts_0054(data ->> 'em') < p_fim
            order by 1 loop
    -- trocas a menos de 1 minuto uma da outra (pausa uma OP e inicia a outra) contam como uma só
    if t - v_pts[array_length(v_pts, 1)] >= interval '1 minute' and p_fim - t >= interval '1 minute' then v_pts := v_pts || t; end if;
  end loop;
  v_pts := v_pts || p_fim;
  for i in 1 .. array_length(v_pts, 1) - 1 loop
    a := v_pts[i]; b := v_pts[i + 1];
    v_op := public.maq_op_em_0054(v_lid, a + (b - a) / 2);
    n := jsonb_array_length(v_out);
    if n > 0 and coalesce(v_op, '') = coalesce(v_ult, '') then
      v_out := jsonb_set(v_out, array[(n - 1)::text, 'fim'], to_jsonb(public.maq_iso_0054(b)));
    else
      v_out := v_out || jsonb_build_object('ini', public.maq_iso_0054(a), 'fim', public.maq_iso_0054(b), 'op', case when v_op is null then null else public.maq_op_info_0054(v_op) end);
    end if;
    v_ult := v_op;
  end loop;
  return v_out;
end $$;
revoke execute on function public.maq_segmentos(timestamptz, timestamptz) from public, anon;
grant execute on function public.maq_segmentos(timestamptz, timestamptz) to authenticated;

-- entrada estimada no estoque da etapa final (quando cabe): ligada ao registro da máquina
create or replace function public.maq_estoque_0054(p_id text, p_doc jsonb, p_linha jsonb, p_maq jsonb)
returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare v_desde timestamptz; v_ini timestamptz := public.maq_ts_0054(p_doc ->> 'ini'); v_item jsonb; v_est text; v_q numeric := public.maq_num_0054(p_doc ->> 'quantidade');
begin
  if not coalesce((p_maq ->> 'producao')::boolean, false) or coalesce(p_doc ->> 'opId', '') = '' or coalesce(v_q, 0) <= 0
     or coalesce((p_doc ->> 'duplicado')::boolean, false) or coalesce(p_doc ->> 'estado', '') = 'anulado' or coalesce(p_doc ->> 'estoqueId', '') <> '' then return null; end if;
  v_desde := public.maq_ts_0054(p_linha -> 'apontaMaquinas' ->> 'desde');
  if v_desde is null or v_ini is null or v_ini < v_desde then return null; end if;
  select it into v_item from jsonb_array_elements(coalesce(public.maq_op_info_0054(p_doc ->> 'opId') -> 'itens', '[]'::jsonb)) it
   where it ->> 'produtoId' = p_doc ->> 'produtoId' limit 1;
  if v_item is null or lower(coalesce(v_item ->> 'unidade', '')) <> lower(coalesce(p_maq ->> 'unidade', '')) then return null; end if;
  v_est := 'mqe-' || substr(p_id, 4);
  insert into public.docs (colecao, id, data) values ('estoque', v_est, jsonb_build_object(
    'tipo', 'entrada', 'porHora', true, 'pendente', true, 'origem', 'maquina', 'maquina', p_maq ->> 'nome', 'maquinaId', p_maq ->> 'id', 'maqReg', p_id,
    'opId', p_doc ->> 'opId', 'produtoId', v_item ->> 'produtoId', 'produtoNome', v_item ->> 'nome', 'unidade', v_item ->> 'unidade',
    'marca', nullif(p_doc ->> 'marca', ''), 'quantidade', round(v_q), 'data', p_doc ->> 'dia', 'hora', p_doc ->> 'horaIni', 'horaFim', p_doc ->> 'horaFim',
    'linha', p_linha ->> 'id', 'turno', coalesce(p_doc ->> 'turno', ''), 'maquinas', '{}'::jsonb, 'paradas', '[]'::jsonb, 'minutosParados', 0, 'obs', '',
    'lider', jsonb_build_object('nome', coalesce(p_doc -> 'operador' ->> 'nome', ''), 'ref', 'membro:' || coalesce(p_doc -> 'operador' ->> 'membro', '')),
    'em', public.maq_iso_0054(now()), 'criadoEm', public.maq_iso_0054(now())))
  on conflict (colecao, id) do nothing;
  update public.docs set data = data || jsonb_build_object('estoqueId', v_est), atualizado_em = now() where colecao = 'producao-maq' and id = p_id;
  return v_est;
end $$;
revoke execute on function public.maq_estoque_0054(text, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- lançamento do tablet: produção do intervalo, início de parada ou retomada
create or replace function public.maq_registrar(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v jsonb := public.maq_minha_0054(); v_l jsonb; v_m jsonb; v_ref text := public.ref_atual();
  v_cid text := regexp_replace(coalesce(p ->> 'id', ''), '[^A-Za-z0-9_-]', '', 'g'); v_id text; v_old jsonb; v_doc jsonb;
  v_tipo text := coalesce(p ->> 'tipo', ''); v_criado timestamptz; v_mb text; v_nm text;
  v_ini timestamptz; v_fim timestamptz; v_op text; v_opinfo jsonb; v_item jsonb;
  v_qtd numeric; v_cont numeric; v_ant numeric; v_reinicio boolean := false; v_prim boolean := false; v_dup boolean; v_est text;
  v_pid text; v_pdoc jsonb;
begin
  if v is null then raise exception 'maquina'; end if;
  if length(v_cid) < 8 or length(v_cid) > 64 then raise exception 'dados'; end if;
  v_l := v -> 'linha'; v_m := v -> 'maquina'; v_id := 'mq-' || v_cid;
  select data into v_old from public.docs where colecao = 'producao-maq' and id = v_id;
  if found then return jsonb_build_object('ok', true, 'id', v_id, 'repetido', true, 'doc', jsonb_build_object('id', v_id) || v_old); end if;
  v_criado := greatest(least(coalesce(public.maq_ts_0054(p ->> 'criadoEm'), now()), now()), now() - interval '7 days');
  -- quem lançou: o operador identificado no tablet naquela hora (com folga para o relógio do tablet)
  select membro, nome into v_mb, v_nm from public.maq_sessoes
   where acesso = v_ref and desde <= v_criado + interval '10 minutes' and (ate is null or ate > v_criado)
   order by desde desc limit 1;
  if v_mb is null then select membro, nome into v_mb, v_nm from public.maq_sessoes where acesso = v_ref and ate is null order by desde desc limit 1; end if;
  if v_mb is null then raise exception 'operador'; end if;

  if v_tipo = 'producao' then
    v_ini := public.maq_ts_0054(p ->> 'ini'); v_fim := public.maq_ts_0054(p ->> 'fim');
    if v_ini is null or v_fim is null or v_fim <= v_ini or v_fim - v_ini > interval '4 hours' then raise exception 'intervalo'; end if;
    if v_fim > now() + interval '5 minutes' then raise exception 'futuro'; end if;
    if v_ini < now() - interval '7 days' then raise exception 'antigo'; end if;
    if exists (select 1 from public.docs where colecao = 'producao-eventos' and data ->> 'linha' = v_l ->> 'id' and data ->> 'tipo' in ('iniciar', 'retomar', 'pausar')
                and public.maq_ts_0054(data ->> 'em') > v_ini + interval '1 minute' and public.maq_ts_0054(data ->> 'em') < v_fim - interval '1 minute') then
      raise exception 'segmentar';
    end if;
    v_op := public.maq_op_em_0054(v_l ->> 'id', v_ini + (v_fim - v_ini) / 2);
    if v_op is not null then
      v_opinfo := public.maq_op_info_0054(v_op);
      select it into v_item from jsonb_array_elements(coalesce(v_opinfo -> 'itens', '[]'::jsonb)) it where it ->> 'produtoId' = p ->> 'produtoId' limit 1;
      if v_item is null then v_item := v_opinfo -> 'itens' -> 0; end if;
    end if;
    if coalesce(v_m ->> 'modo', '') = 'contador' then
      v_cont := public.maq_num_0054(p ->> 'contador');
      if v_cont is null or v_cont < 0 then raise exception 'quantidade'; end if;
      v_ant := public.maq_num_0054(p ->> 'contadorIni');
      if v_ant is null then
        select public.maq_num_0054(data ->> 'contador') into v_ant from public.docs
         where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'producao' and coalesce(data ->> 'estado', '') <> 'anulado'
           and jsonb_typeof(data -> 'contador') = 'number' and public.maq_ts_0054(data ->> 'fim') <= v_ini + interval '1 minute'
         order by public.maq_ts_0054(data ->> 'fim') desc limit 1;
      end if;
      if v_ant is null then v_prim := true;
      elsif v_cont >= v_ant then v_qtd := v_cont - v_ant;
      else v_qtd := v_cont; v_reinicio := true; end if;   -- o contador voltou para o zero
    else
      v_qtd := public.maq_num_0054(p ->> 'quantidade');
      if v_qtd is null or v_qtd < 0 or v_qtd > 10000000 then raise exception 'quantidade'; end if;
    end if;
    v_dup := exists (select 1 from public.docs where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'producao'
                      and coalesce(data ->> 'estado', '') <> 'anulado'
                      and public.maq_ts_0054(data ->> 'ini') < v_fim - interval '1 minute' and public.maq_ts_0054(data ->> 'fim') > v_ini + interval '1 minute');
    v_doc := jsonb_build_object('tipo', 'producao', 'maquinaId', v_m ->> 'id', 'maquina', v_m ->> 'nome', 'linha', v_l ->> 'id', 'acesso', v_ref,
      'operador', jsonb_build_object('membro', v_mb, 'nome', v_nm), 'ini', public.maq_iso_0054(v_ini), 'fim', public.maq_iso_0054(v_fim),
      'dia', left(coalesce(p ->> 'dia', ''), 10), 'turno', left(coalesce(p ->> 'turno', ''), 40),
      'horaIni', to_char(v_ini at time zone 'America/Sao_Paulo', 'HH24:MI'), 'horaFim', to_char(v_fim at time zone 'America/Sao_Paulo', 'HH24:MI'),
      'quantidade', v_qtd, 'unidade', coalesce(v_m ->> 'unidade', ''), 'modo', coalesce(nullif(v_m ->> 'modo', ''), 'intervalo'),
      'contador', v_cont, 'contadorAnterior', v_ant, 'reinicio', v_reinicio, 'primeiraLeitura', v_prim,
      'opId', v_op, 'opNumero', v_opinfo -> 'numero', 'produtoId', v_item ->> 'produtoId', 'produtoNome', v_item ->> 'nome', 'marca', nullif(left(coalesce(p ->> 'marca', ''), 40), ''),
      'final', coalesce((v_m ->> 'producao')::boolean, false), 'duplicado', v_dup, 'retro', now() - v_fim > interval '90 minutes',
      'estado', 'apontado', 'obs', left(coalesce(p ->> 'obs', ''), 200), 'criadoEm', public.maq_iso_0054(v_criado), 'enviadoEm', public.maq_iso_0054(now()));
    insert into public.docs (colecao, id, data) values ('producao-maq', v_id, v_doc);
    v_est := public.maq_estoque_0054(v_id, v_doc, v_l, v_m);
    if v_est is not null then v_doc := v_doc || jsonb_build_object('estoqueId', v_est); end if;
    return jsonb_build_object('ok', true, 'id', v_id, 'doc', jsonb_build_object('id', v_id) || v_doc);

  elsif v_tipo = 'parada' then
    v_ini := coalesce(public.maq_ts_0054(p ->> 'ini'), now());
    v_fim := public.maq_ts_0054(p ->> 'fim');
    if v_ini > now() + interval '5 minutes' or v_ini < now() - interval '2 days' then raise exception 'intervalo'; end if;
    if v_fim is not null and (v_fim <= v_ini or v_fim > now() + interval '5 minutes') then raise exception 'intervalo'; end if;
    if btrim(coalesce(p ->> 'motivo', '')) = '' then raise exception 'motivo'; end if;
    if exists (select 1 from public.docs where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'parada'
                and coalesce(data ->> 'estado', '') <> 'anulado'
                and public.maq_ts_0054(data ->> 'ini') < coalesce(v_fim, 'infinity'::timestamptz)
                and coalesce(public.maq_ts_0054(data ->> 'fim'), 'infinity'::timestamptz) > v_ini) then
      raise exception 'parada_sobreposta';
    end if;
    v_doc := jsonb_build_object('tipo', 'parada', 'maquinaId', v_m ->> 'id', 'maquina', v_m ->> 'nome', 'linha', v_l ->> 'id', 'acesso', v_ref,
      'operador', jsonb_build_object('membro', v_mb, 'nome', v_nm), 'ini', public.maq_iso_0054(v_ini), 'fim', case when v_fim is null then '' else public.maq_iso_0054(v_fim) end,
      'dia', left(coalesce(p ->> 'dia', ''), 10), 'turno', left(coalesce(p ->> 'turno', ''), 40),
      'motivo', left(btrim(p ->> 'motivo'), 80), 'escopo', case when p ->> 'escopo' = 'linha' then 'linha' else 'maquina' end,
      'estado', 'apontado', 'obs', left(coalesce(p ->> 'obs', ''), 200), 'criadoEm', public.maq_iso_0054(v_criado), 'enviadoEm', public.maq_iso_0054(now()));
    insert into public.docs (colecao, id, data) values ('producao-maq', v_id, v_doc);
    return jsonb_build_object('ok', true, 'id', v_id, 'doc', jsonb_build_object('id', v_id) || v_doc);

  elsif v_tipo = 'retomada' then
    select id, data into v_pid, v_pdoc from public.docs
     where colecao = 'producao-maq' and data ->> 'maquinaId' = v_m ->> 'id' and data ->> 'tipo' = 'parada' and coalesce(data ->> 'fim', '') = ''
       and coalesce(data ->> 'estado', '') <> 'anulado' and (coalesce(p ->> 'paradaId', '') = '' or id = p ->> 'paradaId')
     order by data ->> 'ini' desc limit 1;
    if v_pid is null then raise exception 'sem_parada'; end if;
    v_fim := coalesce(public.maq_ts_0054(p ->> 'fim'), now());
    if v_fim <= public.maq_ts_0054(v_pdoc ->> 'ini') or v_fim > now() + interval '5 minutes' then raise exception 'intervalo'; end if;
    update public.docs set data = data || jsonb_build_object('fim', public.maq_iso_0054(v_fim), 'retomadaPor', jsonb_build_object('membro', v_mb, 'nome', v_nm), 'retomadaEm', public.maq_iso_0054(now())),
           atualizado_em = now()
     where colecao = 'producao-maq' and id = v_pid;
    v_doc := jsonb_build_object('tipo', 'retomada', 'maquinaId', v_m ->> 'id', 'maquina', v_m ->> 'nome', 'linha', v_l ->> 'id', 'acesso', v_ref, 'paradaId', v_pid,
      'operador', jsonb_build_object('membro', v_mb, 'nome', v_nm), 'ini', v_pdoc ->> 'ini', 'fim', public.maq_iso_0054(v_fim), 'motivo', v_pdoc ->> 'motivo',
      'dia', left(coalesce(p ->> 'dia', ''), 10), 'estado', 'apontado', 'criadoEm', public.maq_iso_0054(v_criado), 'enviadoEm', public.maq_iso_0054(now()));
    insert into public.docs (colecao, id, data) values ('producao-maq', v_id, v_doc);
    return jsonb_build_object('ok', true, 'id', v_id, 'doc', jsonb_build_object('id', v_id) || v_doc);
  end if;
  raise exception 'tipo';
end $$;
revoke execute on function public.maq_registrar(jsonb) from public, anon;
grant execute on function public.maq_registrar(jsonb) to authenticated;

-- ---------------------------------------------------------------- conferência (PCP e liderança)
create or replace function public.maq_pode_corrigir_0054()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); m jsonb;
begin
  if public.so_inclui() or coalesce((auth.jwt() -> 'app_metadata' ->> 'so_ver')::boolean, false) then return false; end if;
  if coalesce(public.papel_atual(), '') = 'mestre' then return true; end if;
  if coalesce(public.papel_atual(), '') <> 'equipe' or r not like 'escritorio:%' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  return coalesce(m -> 'configuraPcp' = 'true'::jsonb, false) or coalesce(m -> 'confirmaProducao' = 'true'::jsonb, false) or coalesce(m -> 'veLancProducao' = 'true'::jsonb, false);
end $$;
revoke execute on function public.maq_pode_corrigir_0054() from public, anon;
grant execute on function public.maq_pode_corrigir_0054() to authenticated;

create or replace function public.maq_painel(p_de date, p_ate date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(public.papel_atual(), '') not in ('mestre', 'equipe') then raise exception 'permissao'; end if;
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 31 then raise exception 'periodo'; end if;
  return jsonb_build_object(
    'registros', (select coalesce(jsonb_agg(jsonb_build_object('id', id) || data order by data ->> 'ini'), '[]'::jsonb) from public.docs
                   where colecao = 'producao-maq' and (data ->> 'dia' between p_de::text and p_ate::text
                         or (data ->> 'tipo' = 'parada' and coalesce(data ->> 'fim', '') = '' and coalesce(data ->> 'estado', '') <> 'anulado'))),
    'ultimos', (select coalesce(jsonb_object_agg(mq, x), '{}'::jsonb) from (
                  select distinct on (data ->> 'maquinaId') data ->> 'maquinaId' as mq, jsonb_build_object('id', id, 'tipo', data ->> 'tipo', 'ini', data ->> 'ini', 'fim', data ->> 'fim',
                         'quantidade', data -> 'quantidade', 'unidade', data ->> 'unidade', 'enviadoEm', data ->> 'enviadoEm') as x
                    from public.docs where colecao = 'producao-maq' and data ->> 'tipo' in ('producao', 'parada', 'retomada') and coalesce(data ->> 'maquinaId', '') <> ''
                   order by data ->> 'maquinaId', data ->> 'enviadoEm' desc) s),
    'operadores', (select coalesce(jsonb_object_agg(acesso, jsonb_build_object('nome', nome, 'desde', public.maq_iso_0054(desde))), '{}'::jsonb)
                     from public.maq_sessoes where ate is null),
    'podeCorrigir', public.maq_pode_corrigir_0054(),
    'agora', public.maq_iso_0054(now()));
end $$;
revoke execute on function public.maq_painel(date, date) from public, anon;
grant execute on function public.maq_painel(date, date) to authenticated;

-- correção autorizada, com histórico; mantém a entrada estimada do estoque coerente (a confirmada não muda daqui)
create or replace function public.maq_corrigir(p_id text, p_patch jsonb, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb; v_new jsonb; v_set jsonb := '{}'::jsonb; v_info jsonb; v_item jsonb; v_cfg jsonb; v_l jsonb; v_m jsonb; v_est jsonb; v_por jsonb; v_q numeric; k text;
begin
  if not public.maq_pode_corrigir_0054() then raise exception 'permissao'; end if;
  if btrim(coalesce(p_motivo, '')) = '' then raise exception 'motivo'; end if;
  select data into v_old from public.docs where colecao = 'producao-maq' and id = p_id for update;
  if v_old is null then raise exception 'nao_encontrado'; end if;
  v_por := jsonb_build_object('nome', coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', ''), 'ref', coalesce(public.ref_atual(), ''));
  if p_patch ? 'quantidade' then
    v_q := public.maq_num_0054(p_patch ->> 'quantidade');
    if v_q is null or v_q < 0 or v_q > 10000000 then raise exception 'quantidade'; end if;
    v_set := v_set || jsonb_build_object('quantidade', v_q, 'primeiraLeitura', false);
  end if;
  if p_patch ? 'opId' then
    if coalesce(p_patch ->> 'opId', '') = '' then v_set := v_set || jsonb_build_object('opId', null, 'opNumero', null);
    else
      v_info := public.maq_op_info_0054(p_patch ->> 'opId');
      if v_info is null then raise exception 'op'; end if;
      select it into v_item from jsonb_array_elements(v_info -> 'itens') it where it ->> 'produtoId' = coalesce(p_patch ->> 'produtoId', v_old ->> 'produtoId') limit 1;
      if v_item is null then v_item := v_info -> 'itens' -> 0; end if;
      v_set := v_set || jsonb_build_object('opId', v_info ->> 'id', 'opNumero', v_info -> 'numero', 'produtoId', v_item ->> 'produtoId', 'produtoNome', v_item ->> 'nome');
    end if;
  end if;
  if p_patch ? 'estado' then
    if p_patch ->> 'estado' not in ('apontado', 'anulado') then raise exception 'dados'; end if;
    v_set := v_set || jsonb_build_object('estado', p_patch ->> 'estado');
  end if;
  if p_patch ? 'duplicado' then v_set := v_set || jsonb_build_object('duplicado', coalesce((p_patch ->> 'duplicado')::boolean, false)); end if;
  if p_patch ? 'motivo' and v_old ->> 'tipo' = 'parada' then v_set := v_set || jsonb_build_object('motivo', left(btrim(coalesce(p_patch ->> 'motivo', '')), 80)); end if;
  if p_patch ? 'fim' and v_old ->> 'tipo' = 'parada' then
    if public.maq_ts_0054(p_patch ->> 'fim') is null or public.maq_ts_0054(p_patch ->> 'fim') <= public.maq_ts_0054(v_old ->> 'ini') then raise exception 'intervalo'; end if;
    v_set := v_set || jsonb_build_object('fim', public.maq_iso_0054(public.maq_ts_0054(p_patch ->> 'fim')));
  end if;
  if p_patch ? 'obs' then v_set := v_set || jsonb_build_object('obs', left(coalesce(p_patch ->> 'obs', ''), 200)); end if;
  if v_set = '{}'::jsonb then return jsonb_build_object('ok', true, 'doc', jsonb_build_object('id', p_id) || v_old); end if;
  v_new := v_old || v_set || jsonb_build_object('estado', case when v_set ? 'estado' then v_set ->> 'estado' when v_old ->> 'estado' = 'validado' then 'apontado' else coalesce(v_old ->> 'estado', 'apontado') end,
    'corrigidoPor', v_por, 'corrigidoEm', public.maq_iso_0054(now()),
    'historico', coalesce(v_old -> 'historico', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('em', public.maq_iso_0054(now()), 'por', v_por, 'motivo', left(btrim(p_motivo), 200),
      'de', (select coalesce(jsonb_object_agg(k2, v_old -> k2), '{}'::jsonb) from jsonb_object_keys(v_set) k2), 'para', v_set)));
  -- estoque: a entrada estimada acompanha a correção; a já confirmada não muda por aqui
  if coalesce(v_old ->> 'estoqueId', '') <> '' then
    select data into v_est from public.docs where colecao = 'estoque' and id = v_old ->> 'estoqueId';
    if v_est is not null and not coalesce((v_est ->> 'pendente')::boolean, false) then raise exception 'confirmado'; end if;
    if v_est is not null then
      if v_new ->> 'estado' = 'anulado' or coalesce(v_new ->> 'opId', '') = '' or coalesce((v_new ->> 'duplicado')::boolean, false) or coalesce(public.maq_num_0054(v_new ->> 'quantidade'), 0) <= 0 then
        delete from public.docs where colecao = 'estoque' and id = v_old ->> 'estoqueId';
        v_new := v_new - 'estoqueId';
      else
        update public.docs set data = data || jsonb_build_object('quantidade', round(public.maq_num_0054(v_new ->> 'quantidade')), 'opId', v_new ->> 'opId',
               'produtoId', v_new ->> 'produtoId', 'produtoNome', v_new ->> 'produtoNome', 'editadoPor', v_por, 'editadoEm', public.maq_iso_0054(now())), atualizado_em = now()
         where colecao = 'estoque' and id = v_old ->> 'estoqueId';
      end if;
    else v_new := v_new - 'estoqueId';
    end if;
  end if;
  update public.docs set data = v_new, atualizado_em = now() where colecao = 'producao-maq' and id = p_id;
  if v_new ->> 'tipo' = 'producao' and coalesce(v_new ->> 'estoqueId', '') = '' then
    select l - 'maquinas', m into v_l, v_m
      from public.docs d, jsonb_array_elements(d.data -> 'linhas') l, jsonb_array_elements(case when jsonb_typeof(l -> 'maquinas') = 'array' then l -> 'maquinas' else '[]'::jsonb end) m
     where d.colecao = 'mp-config' and d.id = 'linhas-producao' and m ->> 'id' = v_new ->> 'maquinaId' limit 1;
    if v_m is not null and public.maq_estoque_0054(p_id, v_new, v_l, v_m) is not null then
      select data into v_new from public.docs where colecao = 'producao-maq' and id = p_id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'doc', jsonb_build_object('id', p_id) || v_new);
end $$;
revoke execute on function public.maq_corrigir(text, jsonb, text) from public, anon;
grant execute on function public.maq_corrigir(text, jsonb, text) to authenticated;

-- conferido e validado pelo PCP (a entrada no estoque da etapa final é confirmada pelo app, como sempre)
create or replace function public.maq_validar(p_ids text[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare n int; v_por jsonb;
begin
  if not public.maq_pode_corrigir_0054() then raise exception 'permissao'; end if;
  v_por := jsonb_build_object('nome', coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', ''), 'ref', coalesce(public.ref_atual(), ''));
  update public.docs set data = data || jsonb_build_object('estado', 'validado', 'validadoPor', v_por, 'validadoEm', public.maq_iso_0054(now())), atualizado_em = now()
   where colecao = 'producao-maq' and id = any (coalesce(p_ids, '{}'::text[])) and coalesce(data ->> 'estado', '') <> 'anulado';
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'validados', n);
end $$;
revoke execute on function public.maq_validar(text[]) from public, anon;
grant execute on function public.maq_validar(text[]) to authenticated;

-- ---------------------------------------------------------------- só o PCP administra a OP (também no banco)
create or replace function public.producao_adm_guarda_0054()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(public.papel_atual(), '') = '' then return new; end if; -- migrações e funções internas
  if new.colecao = 'producao-eventos' and tg_op = 'INSERT' and coalesce(new.data ->> 'tipo', '') in ('iniciar', 'pausar', 'retomar') and not public.pcp_configura_0052() then
    raise exception 'pcp: iniciar, pausar e retomar a OP é do PCP (senha mestre ou Configura o PCP)';
  end if;
  if new.colecao = 'producao-ordens' and tg_op = 'UPDATE' and coalesce(new.data ->> 'status', '') = 'concluida' and coalesce(old.data ->> 'status', '') <> 'concluida'
     and not public.pcp_configura_0052() then
    raise exception 'pcp: concluir a OP é do PCP (senha mestre ou Configura o PCP)';
  end if;
  return new;
end $$;
revoke execute on function public.producao_adm_guarda_0054() from public, anon, authenticated;
drop trigger if exists producao_adm_guarda_0054 on public.docs;
create trigger producao_adm_guarda_0054 before insert or update on public.docs
  for each row when (new.colecao in ('producao-eventos', 'producao-ordens')) execute function public.producao_adm_guarda_0054();

-- ---------------------------------------------------------------- configuração das linhas: o que "Configura o PCP" muda nas máquinas
create or replace function public.pcp_linhas_guarda_0052()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  lo jsonb; ln jsonb; a jsonb; b jsonb; ma jsonb; mb jsonb; i int; j int; nome text;
begin
  -- só quem entra pela senha da equipe tem a regra (a senha mestre muda tudo)
  if coalesce(public.papel_atual(), '') <> 'equipe' then return new; end if;
  if tg_op = 'INSERT' then
    if exists (select 1 from public.docs where colecao = new.colecao and id = new.id) then return new; end if; -- vira atualização
    raise exception 'pcp: só a senha mestre cria a configuração das linhas';
  end if;
  lo := coalesce(old.data -> 'linhas', '[]'::jsonb);
  ln := coalesce(new.data -> 'linhas', '[]'::jsonb);
  if jsonb_typeof(ln) <> 'array' or jsonb_typeof(lo) <> 'array' or jsonb_array_length(ln) <> jsonb_array_length(lo) then
    raise exception 'pcp: só a senha mestre inclui ou tira linhas';
  end if;
  for i in 0 .. jsonb_array_length(lo) - 1 loop
    a := lo -> i; b := ln -> i;
    if (a -> 'id') is distinct from (b -> 'id') or (a -> 'nome') is distinct from (b -> 'nome') or (a -> 'un') is distinct from (b -> 'un')
       or (a -> 'produtos') is distinct from (b -> 'produtos') or (a -> 'op') is distinct from (b -> 'op') or (a -> 'metaId') is distinct from (b -> 'metaId') then
      raise exception 'pcp: só a senha mestre muda o nome, a unidade e os produtos da linha';
    end if;
    -- máquinas: "Configura o PCP" muda unidade, modo de contagem, etapa final, capacidade e se é obrigatória;
    -- incluir ou tirar máquina e mudar o nome, o id ou o acesso do tablet continuam só da senha mestre
    ma := case when jsonb_typeof(a -> 'maquinas') = 'array' then a -> 'maquinas' else '[]'::jsonb end;
    mb := case when jsonb_typeof(b -> 'maquinas') = 'array' then b -> 'maquinas' else '[]'::jsonb end;
    if jsonb_array_length(ma) <> jsonb_array_length(mb) then raise exception 'pcp: só a senha mestre inclui ou tira máquinas'; end if;
    for j in 0 .. jsonb_array_length(ma) - 1 loop
      if (ma -> j -> 'id') is distinct from (mb -> j -> 'id') or (ma -> j -> 'nome') is distinct from (mb -> j -> 'nome') or (ma -> j -> 'acesso') is distinct from (mb -> j -> 'acesso') then
        raise exception 'pcp: só a senha mestre muda o nome e o acesso das máquinas';
      end if;
    end loop;
    for nome in select public.pcp_turno_nome_0052(t) from jsonb_array_elements(coalesce(a -> 'turnos', '[]'::jsonb)) t loop
      if nome <> '' and not exists (select 1 from jsonb_array_elements(coalesce(b -> 'turnos', '[]'::jsonb)) t2 where public.pcp_turno_nome_0052(t2) = nome) then
        raise exception 'pcp: o turno % não pode sumir nem mudar de nome (só a senha mestre)', nome;
      end if;
    end loop;
  end loop;
  return new;
end $$;
revoke execute on function public.pcp_linhas_guarda_0052() from public, anon, authenticated;
