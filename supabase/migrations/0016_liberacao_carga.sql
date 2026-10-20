-- LEVÍSSIMA · 0016: liberação de carga sem leitura do código de barras e sem fotos do caminhão, pedido de 19/10/2026.
--
-- Só a senha mestre (não a diretoria "só inclui") e quem tem a permissão "liberar_carga" no acesso individual
-- (Cadastros › Equipe com senha › Acesso ao app) podem liberar uma carga para concluir sem a dupla conferência por
-- código de barras e sem as fotos do caminhão (antes de lonar, na expedição, e lonado, no app do motorista).
-- A liberação fica registrada na própria carga (campo "excecao": quem liberou, quando e o motivo) e aparece como
-- observação na carga e na ordem de carregamento.
--
-- Só a função carga_excecao grava esse campo: um gatilho recusa qualquer outra gravação que crie ou mude a
-- liberação (ninguém consegue registrar uma liberação em nome de outra pessoa). Gravar a carga com a liberação
-- igual (ex.: ao concluir) ou sem ela continua normal.

create or replace function public.pode_liberar_carga()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'mestre' and not public.so_inclui())
      or (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'equipe'
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'liberar_carga', false));
$$;
revoke execute on function public.pode_liberar_carga() from public, anon;
grant execute on function public.pode_liberar_carga() to authenticated;

-- gatilho: a liberação só nasce ou muda pela função carga_excecao
create or replace function public.cargas_protege_excecao()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  nova jsonb;
  antiga jsonb;
begin
  if new.colecao <> 'cargas' then return new; end if;
  if coalesce(current_setting('levissima.excecao', true), '') = '1' then return new; end if;
  nova := new.data -> 'excecao';
  if nova is null or jsonb_typeof(nova) = 'null' then return new; end if;
  if tg_op = 'UPDATE' then
    antiga := old.data -> 'excecao';
  else
    -- insert com "on conflict do update" (gravação da carga inteira): compara com o que já está gravado
    select d.data -> 'excecao' into antiga from public.docs d where d.colecao = new.colecao and d.id = new.id;
  end if;
  if antiga is not distinct from nova then return new; end if;
  raise exception 'excecao_carga' using errcode = '42501';
end $$;
revoke execute on function public.cargas_protege_excecao() from public, anon, authenticated;

create or replace trigger docs_protege_excecao_0016 before insert or update on public.docs
  for each row execute function public.cargas_protege_excecao();

-- liberar (com motivo) ou desfazer a liberação de uma carga que ainda não foi concluída
create or replace function public.carga_excecao(p_carga text, p_acao text, p_motivo text default '')
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c jsonb;
  novo jsonb;
  motivo text := left(btrim(coalesce(p_motivo, '')), 300);
  agora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if not public.pode_liberar_carga() then raise exception 'permissao' using errcode = '42501'; end if;
  select d.data into c from public.docs d where d.colecao = 'cargas' and d.id = p_carga for update;
  if c is null then raise exception 'carga' using errcode = 'P0002'; end if;
  perform set_config('levissima.excecao', '1', true);
  if p_acao = 'liberar' then
    if length(motivo) < 3 then raise exception 'motivo' using errcode = '22023'; end if;
    novo := c || jsonb_build_object('excecao', jsonb_build_object(
      'semConferencia', true, 'semFotos', true, 'motivo', motivo,
      'por', public.nome_atual(), 'porRef', public.ref_atual(), 'em', agora));
  elsif p_acao = 'desfazer' then
    if coalesce(c ->> 'status', '') = 'concluida' then raise exception 'concluida' using errcode = '22023'; end if;
    novo := c - 'excecao';
  else
    raise exception 'acao' using errcode = '22023';
  end if;
  update public.docs set data = novo, atualizado_em = now() where colecao = 'cargas' and id = p_carga;
  perform set_config('levissima.excecao', '', true);
  return novo;
end $$;
revoke execute on function public.carga_excecao(text, text, text) from public, anon;
grant execute on function public.carga_excecao(text, text, text) to authenticated;
