-- LEVÍSSIMA · 0025: editar, apagar e reagir no chat (pedido de 20/10/2026).
--
-- * Editar: cada um edita a PRÓPRIA mensagem (Chat e Solicitações), a qualquer hora; fica marcada como editada
--   (editada_em) para os dois. Mensagem apagada não se edita.
-- * Apagar: cada um apaga a PRÓPRIA mensagem a qualquer hora (antes era só até 1 hora depois); a senha mestre continua
--   apagando qualquer mensagem das conversas dela. O texto some do banco ("(mensagem apagada)").
-- * Reagir: 👍 ou 👎 em qualquer mensagem da conversa (reacoes = { ref: '👍' | '👎' }); um por pessoa e por mensagem,
--   tocar de novo tira. Os dois veem na hora (tempo real).
-- Tudo só pelas funções abaixo, que conferem quem está logado (ninguém grava direto na tabela).

alter table public.chat_msgs add column if not exists editada_em timestamptz;
alter table public.chat_msgs add column if not exists reacoes jsonb not null default '{}'::jsonb;

-- editar a própria mensagem
create or replace function public.chat_editar(p_id bigint, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  select * into r from public.chat_msgs m where m.id = p_id and m.de = v_eu for update;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  if r.apagada then raise exception 'apagada' using errcode = '22023'; end if;
  if r.texto = v_txt then return to_jsonb(r); end if;
  update public.chat_msgs m set texto = v_txt, editada_em = now() where m.id = p_id returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_editar(bigint, text) from public, anon;
grant execute on function public.chat_editar(bigint, text) to authenticated;

-- apagar: a própria mensagem a qualquer hora; a senha mestre, qualquer uma das conversas dela
create or replace function public.chat_apagar(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  select * into r from public.chat_msgs m where m.id = p_id and (m.de = v_eu or m.para = v_eu) for update;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  if r.apagada then return to_jsonb(r); end if;
  if not (v_eu = 'mestre' or r.de = v_eu) then raise exception 'permissao' using errcode = '42501'; end if;
  update public.chat_msgs m set apagada = true, apagada_em = now(), apagada_por = v_eu, texto = '(mensagem apagada)',
         lida = true, resolvido = null, reacoes = '{}'::jsonb
   where m.id = p_id returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_apagar(bigint) from public, anon;
grant execute on function public.chat_apagar(bigint) to authenticated;

-- reagir com 👍 ou 👎 (p_reacao nulo ou vazio tira a reação)
create or replace function public.chat_reagir(p_id bigint, p_reacao text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_r text := nullif(btrim(coalesce(p_reacao, '')), '');
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_r is not null and v_r not in ('👍', '👎') then raise exception 'reacao' using errcode = '22023'; end if;
  select * into r from public.chat_msgs m where m.id = p_id and m.tipo = 'chat' and (m.de = v_eu or m.para = v_eu) for update;
  if r.id is null then raise exception 'permissao' using errcode = '42501'; end if;
  if r.apagada then raise exception 'apagada' using errcode = '22023'; end if;
  update public.chat_msgs m
     set reacoes = case when v_r is null then coalesce(m.reacoes, '{}'::jsonb) - v_eu
                        else coalesce(m.reacoes, '{}'::jsonb) || jsonb_build_object(v_eu, v_r) end
   where m.id = p_id returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_reagir(bigint, text) from public, anon;
grant execute on function public.chat_reagir(bigint, text) to authenticated;
