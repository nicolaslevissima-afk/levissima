-- LEVÍSSIMA · 0015: controle de canhotos (foto do canhoto assinado) e fotos do caminhão, pedido de 18/10/2026.
--
-- Referência: Canhoto Fácil (Varitus) — o canhoto da NF assinado pelo cliente é fotografado na entrega, com data,
-- hora e local, e o escritório acompanha e confere num painel.
--
-- Quem VÊ os canhotos e as fotos do caminhão:
--   * senha mestre e acessos da diretoria (papel 'mestre' no login);
--   * as pessoas do escritório com acesso individual e a permissão "canhotos" (logística, financeiro,
--     faturamento e comercial; a permissão é marcada em Cadastros › Acesso ao app);
--   * o representante do cliente: só os canhotos dos clientes dele e as fotos do caminhão das cargas desses clientes.
-- Quem ENVIA foto: o motorista (canhoto da entrega dele e o caminhão lonado), o conferente (caminhão antes de lonar,
-- no app com a senha mestre ou da equipe) e o escritório. Foto enviada não é trocada; só a senha mestre apaga.
--
-- Coleções (tabela docs):
--   canhotos           um documento por entrega (id = id do registro da entrega). Só as funções abaixo gravam.
--   carteira-clientes  cliente → representante (aprendida dos pedidos da força de vendas e ajustada no controle).
-- Arquivos: bucket privado "canhotos": entregas/<entrega>/<foto> e caminhao/<carga>/<conferencia|motorista>-<lado>-<foto>.
-- As fotos do caminhão ficam marcadas na própria carga (campo fotosCaminhao); o representante as vê pela função
-- fotos_caminhao (ele não lê as cargas do escritório).

-- ---------- quem é quem ----------
create or replace function public.nome_atual()
returns text
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', ''); $$;
revoke execute on function public.nome_atual() from public, anon;
grant execute on function public.nome_atual() to authenticated;

create or replace function public.ve_canhotos()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'mestre'
      or (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'equipe'
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'canhotos', false));
$$;
revoke execute on function public.ve_canhotos() from public, anon;
grant execute on function public.ve_canhotos() to authenticated;

-- chave do cliente na carteira: pelo CPF/CNPJ (números e letras) ou, sem documento, pelo nome sem acento
create or replace function public.chave_cliente(p_doc text, p_nome text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when length(regexp_replace(upper(coalesce(p_doc, '')), '[^0-9A-Z]', '', 'g')) in (11, 14)
      then 'doc-' || lower(regexp_replace(upper(p_doc), '[^0-9A-Z]', '', 'g'))
    else 'nome-' || left(trim(both '-' from regexp_replace(lower(translate(coalesce(p_nome, ''),
      'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ', 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn')),
      '[^a-z0-9]+', '-', 'g')), 120)
  end;
$$;
revoke execute on function public.chave_cliente(text, text) from public, anon;
grant execute on function public.chave_cliente(text, text) to authenticated;

-- ---------- regras das coleções ----------
do $$
begin
  -- canhotos: leem quem vê e o representante do cliente; ninguém grava direto (só as funções)
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'canhotos_le_0015') then
    create policy "canhotos_le_0015" on public.docs as restrictive for select to authenticated
      using (colecao <> 'canhotos' or (select public.ve_canhotos())
             or ((select public.papel_atual()) = 'representante' and data ->> 'representanteRef' = (select public.ref_atual())));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'canhotos_rep_le_0015') then
    create policy "canhotos_rep_le_0015" on public.docs for select to authenticated
      using (colecao = 'canhotos' and (select public.papel_atual()) = 'representante'
             and data ->> 'representanteRef' = (select public.ref_atual()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'carteira_le_0015') then
    create policy "carteira_le_0015" on public.docs as restrictive for select to authenticated
      using (colecao <> 'carteira-clientes' or (select public.ve_canhotos()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'canhotos_grava_0015') then
    create policy "canhotos_grava_0015" on public.docs as restrictive for insert to authenticated
      with check (colecao not in ('canhotos', 'carteira-clientes'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'canhotos_altera_0015') then
    create policy "canhotos_altera_0015" on public.docs as restrictive for update to authenticated
      using (colecao not in ('canhotos', 'carteira-clientes'))
      with check (colecao not in ('canhotos', 'carteira-clientes'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'canhotos_apaga_0015') then
    create policy "canhotos_apaga_0015" on public.docs as restrictive for delete to authenticated
      using (colecao not in ('canhotos', 'carteira-clientes') or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

-- ---------- montagem do canhoto a partir da entrega (uso interno) ----------
create or replace function public.canhoto_base(p_registro text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  r jsonb;
  c jsonb;
  cart jsonb;
  rep_ref text := '';
  rep_nome text := '';
  nome_cad text;
  k1 text;
  k2 text;
begin
  select d.data into r from public.docs d where d.colecao = 'registros' and d.id = p_registro;
  if r is null then return null; end if;
  if coalesce(r ->> 'cargaId', '') <> '' then
    select d.data into c from public.docs d where d.colecao = 'cargas' and d.id = r ->> 'cargaId';
  end if;
  rep_ref := coalesce(c ->> 'representanteRef', '');
  rep_nome := coalesce(c ->> 'representanteNome', '');
  if rep_ref = '' then
    k1 := public.chave_cliente(r ->> 'numeroDocumento', r ->> 'cliente');
    k2 := public.chave_cliente(null, r ->> 'cliente');
    select d.data into cart from public.docs d
     where d.colecao = 'carteira-clientes' and d.id in (k1, k2) and coalesce(d.data ->> 'representanteRef', '') <> ''
     order by (d.id = k1) desc limit 1;
    rep_ref := coalesce(cart ->> 'representanteRef', '');
    rep_nome := coalesce(cart ->> 'representanteNome', '');
  end if;
  if rep_ref like 'representante:%' then
    select d.data ->> 'nome' into nome_cad from public.docs d where d.colecao = 'representantes' and d.id = substr(rep_ref, 15);
    if coalesce(nome_cad, '') <> '' then rep_nome := nome_cad; end if;
  end if;
  return jsonb_build_object(
    'registroId', p_registro,
    'cargaId', coalesce(r ->> 'cargaId', ''),
    'cliente', coalesce(r ->> 'cliente', ''),
    'documento', coalesce(r ->> 'numeroDocumento', ''),
    'nf', coalesce(r ->> 'nfNumero', ''),
    'pedidoNf', coalesce(r ->> 'pedidoNf', ''),
    'motorista', coalesce(r ->> 'motorista', ''),
    'dataCarga', coalesce(c ->> 'data', r ->> 'data', ''),
    'ordemEntrega', coalesce(r -> 'ordemEntrega', 'null'::jsonb),
    'representanteRef', rep_ref,
    'representanteNome', coalesce(rep_nome, ''),
    'entregue', coalesce(r ->> 'status', '') = 'concluido',
    'entregueEm', case when coalesce(r ->> 'status', '') = 'concluido' then coalesce(r ->> 'concluidoEm', '') else '' end,
    'recebidoPor', coalesce(r ->> 'responsavel', ''));
end $$;
revoke execute on function public.canhoto_base(text) from public, anon, authenticated;

-- grava o canhoto (cria se ainda não existe), acrescenta fotos e espelha a situação na entrega (uso interno)
create or replace function public.canhoto_gravar(p_registro text, p_fotos jsonb, p_motivo text, p_loc jsonb, p_quem text, p_papel text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  atual jsonb;
  base jsonb;
  novo jsonb;
  f jsonb;
  fotos jsonb;
  hist jsonb;
  n_novas int := 0;
  motivo text := left(btrim(coalesce(p_motivo, '')), 200);
  agora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  loc jsonb := null;
  padrao text;
begin
  if p_registro !~ '^[A-Za-z0-9_-]{1,120}$' then raise exception 'entrega' using errcode = '22023'; end if;
  base := public.canhoto_base(p_registro);
  if base is null then raise exception 'entrega' using errcode = 'P0002'; end if;
  p_fotos := coalesce(p_fotos, '[]'::jsonb);
  if jsonb_typeof(p_fotos) <> 'array' or jsonb_array_length(p_fotos) > 4 then raise exception 'fotos' using errcode = '22023'; end if;
  padrao := '^entregas/' || p_registro || '/[A-Za-z0-9_.-]{1,120}$';
  for f in select * from jsonb_array_elements(p_fotos) loop
    if jsonb_typeof(f) <> 'string' or (f #>> '{}') !~ padrao then raise exception 'fotos' using errcode = '22023'; end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'canhotos' and o.name = (f #>> '{}')) then
      raise exception 'foto_nao_enviada' using errcode = '22023';
    end if;
  end loop;
  if p_loc is not null and jsonb_typeof(p_loc) = 'object' and length(p_loc::text) <= 300
     and jsonb_typeof(p_loc -> 'lat') = 'number' and jsonb_typeof(p_loc -> 'lng') = 'number' then
    loc := jsonb_build_object('lat', p_loc -> 'lat', 'lng', p_loc -> 'lng', 'acc', coalesce(p_loc -> 'acc', 'null'::jsonb));
  end if;

  select d.data into atual from public.docs d where d.colecao = 'canhotos' and d.id = p_registro for update;
  if atual is null then
    novo := base || jsonb_build_object('status', 'pendente', 'fotos', '[]'::jsonb, 'criadoEm', agora, 'historico', '[]'::jsonb);
  else
    novo := atual || (base - 'representanteRef' - 'representanteNome');
    if coalesce(atual ->> 'representanteRef', '') = '' and base ->> 'representanteRef' <> '' then
      novo := novo || jsonb_build_object('representanteRef', base ->> 'representanteRef', 'representanteNome', base ->> 'representanteNome');
    end if;
  end if;

  fotos := coalesce(novo -> 'fotos', '[]'::jsonb);
  for f in select * from jsonb_array_elements(p_fotos) loop
    if not (fotos @> jsonb_build_array(f)) then fotos := fotos || jsonb_build_array(f); n_novas := n_novas + 1; end if;
  end loop;
  if jsonb_array_length(fotos) > 12 then raise exception 'fotos' using errcode = '22023'; end if;
  novo := novo || jsonb_build_object('fotos', fotos);

  if n_novas > 0 then
    novo := (novo - 'problema') || jsonb_build_object('status', 'enviado', 'enviadoEm', agora, 'enviadoPor', coalesce(p_quem, ''),
      'enviadoPapel', coalesce(p_papel, ''), 'enviadoLoc', coalesce(loc, 'null'::jsonb), 'motivoSemFoto', '');
    hist := jsonb_build_object('em', agora, 'por', coalesce(p_quem, ''), 'acao', 'foto', 'n', n_novas);
  elsif motivo <> '' and coalesce(novo ->> 'status', 'pendente') = 'pendente' and coalesce(novo ->> 'motivoSemFoto', '') <> motivo then
    novo := novo || jsonb_build_object('motivoSemFoto', motivo);
    hist := jsonb_build_object('em', agora, 'por', coalesce(p_quem, ''), 'acao', 'sem_foto', 'motivo', motivo);
  end if;
  if hist is not null then
    novo := jsonb_set(novo, '{historico}', coalesce(novo -> 'historico', '[]'::jsonb) || jsonb_build_array(hist));
  end if;

  insert into public.docs (colecao, id, data, atualizado_em) values ('canhotos', p_registro, novo, now())
  on conflict (colecao, id) do update set data = excluded.data, atualizado_em = now();
  perform public.canhoto_espelhar(p_registro, novo);
  return novo;
end $$;

-- a situação do canhoto também fica na entrega: é por ela que o motorista vê se precisa refazer a foto
create or replace function public.canhoto_espelhar(p_registro text, p_canhoto jsonb)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.docs
     set data = jsonb_set(data, '{canhoto}', jsonb_build_object(
           'status', coalesce(p_canhoto ->> 'status', 'pendente'),
           'em', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'n', jsonb_array_length(coalesce(p_canhoto -> 'fotos', '[]'::jsonb)),
           'fotos', coalesce(p_canhoto -> 'fotos', '[]'::jsonb),
           'motivo', coalesce(p_canhoto ->> 'motivoSemFoto', ''),
           'problema', coalesce(p_canhoto #>> '{problema,motivo}', ''))),
         atualizado_em = now()
   where colecao = 'registros' and id = p_registro;
$$;
revoke execute on function public.canhoto_gravar(text, jsonb, text, jsonb, text, text) from public, anon, authenticated;
revoke execute on function public.canhoto_espelhar(text, jsonb) from public, anon, authenticated;

-- ---------- funções que o app chama ----------
-- Foto do canhoto (ou o motivo de não ter foto agora). Motorista: só a entrega dele. Escritório e senha mestre: qualquer.
create or replace function public.canhoto_registrar(p_registro text, p_fotos jsonb default '[]'::jsonb, p_motivo text default '', p_loc jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  papel text := public.papel_atual();
  quem text := public.nome_atual();
  dono text;
begin
  if papel not in ('mestre', 'equipe', 'motorista') then raise exception 'permissao' using errcode = '42501'; end if;
  if papel = 'motorista' then
    select d.data ->> 'motorista' into dono from public.docs d where d.colecao = 'registros' and d.id = p_registro;
    if dono is null or dono <> quem then raise exception 'permissao' using errcode = '42501'; end if;
  end if;
  return public.canhoto_gravar(p_registro, p_fotos, p_motivo, p_loc, quem, papel);
end $$;
revoke execute on function public.canhoto_registrar(text, jsonb, text, jsonb) from public, anon;
grant execute on function public.canhoto_registrar(text, jsonb, text, jsonb) to authenticated;

-- Abre os canhotos que ainda não existem (ao concluir o carregamento e ao abrir o controle).
-- Usa a foto e o motivo que já estiverem na entrega, se a gravação do canhoto tiver falhado antes.
create or replace function public.canhotos_abrir(p_registros jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  papel text := public.papel_atual();
  rid text;
  r jsonb;
  n int := 0;
begin
  if papel not in ('mestre', 'equipe') then raise exception 'permissao' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_registros, '[]'::jsonb)) <> 'array' or jsonb_array_length(p_registros) > 300 then
    raise exception 'dados' using errcode = '22023';
  end if;
  for rid in select jsonb_array_elements_text(p_registros) loop
    if rid !~ '^[A-Za-z0-9_-]{1,120}$' then continue; end if;
    if exists (select 1 from public.docs d where d.colecao = 'canhotos' and d.id = rid) then continue; end if;
    select d.data into r from public.docs d where d.colecao = 'registros' and d.id = rid;
    if r is null or coalesce(r ->> 'tipo', 'entrega') <> 'entrega' then continue; end if;
    begin
      perform public.canhoto_gravar(rid, coalesce(r #> '{canhoto,fotos}', '[]'::jsonb), coalesce(r #>> '{canhoto,motivo}', ''), null,
        coalesce(r #>> '{canhoto,por}', r ->> 'motorista', ''), 'sincronizado');
      n := n + 1;
    exception when others then
      perform public.canhoto_gravar(rid, '[]'::jsonb, '', null, '', 'sincronizado');
      n := n + 1;
    end;
  end loop;
  return n;
end $$;
revoke execute on function public.canhotos_abrir(jsonb) from public, anon;
grant execute on function public.canhotos_abrir(jsonb) to authenticated;

-- Conferência do escritório: conferido, refazer foto (com motivo), reabrir, canhoto em papel recebido.
create or replace function public.canhoto_marcar(p_id text, p_acao text, p_motivo text default '')
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  atual jsonb;
  novo jsonb;
  quem text := public.nome_atual();
  agora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  motivo text := left(btrim(coalesce(p_motivo, '')), 200);
  nfotos int;
begin
  if not public.ve_canhotos() or public.so_inclui() then raise exception 'permissao' using errcode = '42501'; end if;
  select d.data into atual from public.docs d where d.colecao = 'canhotos' and d.id = p_id for update;
  if atual is null then raise exception 'canhoto' using errcode = 'P0002'; end if;
  nfotos := jsonb_array_length(coalesce(atual -> 'fotos', '[]'::jsonb));
  if p_acao = 'conferido' then
    if nfotos = 0 then raise exception 'sem_foto' using errcode = '22023'; end if;
    novo := (atual - 'problema') || jsonb_build_object('status', 'conferido', 'conferidoEm', agora, 'conferidoPor', quem);
  elsif p_acao = 'problema' then
    if motivo = '' then raise exception 'motivo' using errcode = '22023'; end if;
    novo := atual || jsonb_build_object('status', 'problema', 'problema', jsonb_build_object('motivo', motivo, 'em', agora, 'por', quem));
  elsif p_acao = 'reabrir' then
    novo := (atual - 'problema' - 'conferidoEm' - 'conferidoPor') || jsonb_build_object('status', case when nfotos > 0 then 'enviado' else 'pendente' end);
  elsif p_acao = 'fisico' then
    novo := atual || jsonb_build_object('fisico', jsonb_build_object('em', agora, 'por', quem, 'obs', motivo));
  elsif p_acao = 'fisico_desfazer' then
    novo := atual - 'fisico';
  else
    raise exception 'acao' using errcode = '22023';
  end if;
  novo := jsonb_set(novo, '{historico}', coalesce(novo -> 'historico', '[]'::jsonb) ||
    jsonb_build_array(jsonb_build_object('em', agora, 'por', quem, 'acao', p_acao, 'motivo', motivo)));
  update public.docs set data = novo, atualizado_em = now() where colecao = 'canhotos' and id = p_id;
  perform public.canhoto_espelhar(p_id, novo);
  return novo;
end $$;
revoke execute on function public.canhoto_marcar(text, text, text) from public, anon;
grant execute on function public.canhoto_marcar(text, text, text) to authenticated;

-- Representante do cliente do canhoto (guarda na carteira; opcional: vale também para os outros canhotos
-- desse cliente que estão sem representante). p_ref vazio tira o representante.
create or replace function public.canhoto_representante(p_id text, p_ref text, p_todos boolean default true)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  atual jsonb;
  nome text := '';
  ref text := coalesce(p_ref, '');
  quem text := public.nome_atual();
  agora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  k1 text;
  k2 text;
  n int := 0;
begin
  if not public.ve_canhotos() or public.so_inclui() then raise exception 'permissao' using errcode = '42501'; end if;
  select d.data into atual from public.docs d where d.colecao = 'canhotos' and d.id = p_id for update;
  if atual is null then raise exception 'canhoto' using errcode = 'P0002'; end if;
  if ref <> '' then
    if ref !~ '^representante:[A-Za-z0-9_-]{1,64}$' then raise exception 'representante' using errcode = '22023'; end if;
    select d.data ->> 'nome' into nome from public.docs d where d.colecao = 'representantes' and d.id = substr(ref, 15);
    if nome is null then raise exception 'representante' using errcode = 'P0002'; end if;
  end if;
  update public.docs set data = data || jsonb_build_object('representanteRef', ref, 'representanteNome', coalesce(nome, '')), atualizado_em = now()
   where colecao = 'canhotos' and id = p_id;
  n := 1;
  k1 := public.chave_cliente(atual ->> 'documento', atual ->> 'cliente');
  k2 := public.chave_cliente(null, atual ->> 'cliente');
  insert into public.docs (colecao, id, data, atualizado_em)
  select 'carteira-clientes', k, jsonb_build_object('cliente', atual ->> 'cliente', 'documento', coalesce(atual ->> 'documento', ''),
           'representanteRef', ref, 'representanteNome', coalesce(nome, ''), 'em', agora, 'por', quem), now()
    from unnest(array[k1, k2]) as k
   group by k
  on conflict (colecao, id) do update set data = excluded.data, atualizado_em = now();
  if p_todos and ref <> '' then
    update public.docs d
       set data = d.data || jsonb_build_object('representanteRef', ref, 'representanteNome', nome), atualizado_em = now()
     where d.colecao = 'canhotos' and d.id <> p_id and coalesce(d.data ->> 'representanteRef', '') = ''
       and (public.chave_cliente(d.data ->> 'documento', d.data ->> 'cliente') = k1 or public.chave_cliente(null, d.data ->> 'cliente') = k2);
    get diagnostics n = row_count;
    n := n + 1;
  end if;
  return n;
end $$;
revoke execute on function public.canhoto_representante(text, text, boolean) from public, anon;
grant execute on function public.canhoto_representante(text, text, boolean) to authenticated;

-- Lista dos representantes (só nome e ref) para quem confere os canhotos escolher o do cliente.
create or replace function public.canhotos_representantes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.ve_canhotos() then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ref', 'representante:' || d.id, 'nome', coalesce(d.data ->> 'nome', '')) order by d.data ->> 'nome')
                     from public.docs d where d.colecao = 'representantes'), '[]'::jsonb);
end $$;
revoke execute on function public.canhotos_representantes() from public, anon;
grant execute on function public.canhotos_representantes() to authenticated;

-- O representante tem canhoto nesta carga? (usado nas regras dos arquivos e das fotos do caminhão)
create or replace function public.rep_tem_canhoto(p_carga text, p_entrega text default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.papel_atual() = 'representante' and exists (
    select 1 from public.docs d
     where d.colecao = 'canhotos' and d.data ->> 'representanteRef' = public.ref_atual()
       and ((p_entrega is not null and d.id = p_entrega) or (p_carga is not null and d.data ->> 'cargaId' = p_carga)));
$$;
revoke execute on function public.rep_tem_canhoto(text, text) from public, anon;
grant execute on function public.rep_tem_canhoto(text, text) to authenticated;

-- Fotos do caminhão de uma carga (conferência antes de lonar e o motorista com o caminhão lonado).
create or replace function public.fotos_caminhao(p_carga text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  c jsonb;
begin
  if not (public.ve_canhotos() or public.rep_tem_canhoto(p_carga, null)) then raise exception 'permissao' using errcode = '42501'; end if;
  select d.data into c from public.docs d where d.colecao = 'cargas' and d.id = p_carga;
  if c is null then return null; end if;
  return jsonb_build_object('cargaId', p_carga, 'data', coalesce(c ->> 'data', ''), 'motorista', coalesce(c ->> 'motorista', ''),
    'concluidoEm', coalesce(c ->> 'concluidoEm', ''), 'fotosCaminhao', coalesce(c -> 'fotosCaminhao', '{}'::jsonb));
end $$;
revoke execute on function public.fotos_caminhao(text) from public, anon;
grant execute on function public.fotos_caminhao(text) to authenticated;

-- ---------- arquivos ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('canhotos', 'canhotos', false, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'canhotos: envia') then
    create policy "canhotos: envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'canhotos' and (select public.papel_atual()) in ('mestre', 'equipe', 'motorista')
                  and (name ~ '^entregas/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$'
                       or name ~ '^caminhao/[A-Za-z0-9_-]{1,120}/(conferencia|motorista)-(esquerdo|direito)-[A-Za-z0-9_.-]{1,100}$'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'canhotos: quem ve le') then
    create policy "canhotos: quem ve le" on storage.objects for select to authenticated
      using (bucket_id = 'canhotos' and ((select public.ve_canhotos())
             or (name like 'entregas/%' and public.rep_tem_canhoto(null, split_part(name, '/', 2)))
             or (name like 'caminhao/%' and public.rep_tem_canhoto(split_part(name, '/', 2), null))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'canhotos: mestre apaga') then
    create policy "canhotos: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'canhotos' and (select public.papel_atual()) = 'mestre');
  end if;
end $$;
