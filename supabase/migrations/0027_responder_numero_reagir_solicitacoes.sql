-- LEVÍSSIMA · 0027: responder uma mensagem, número de cada solicitação e 👍/👎 nas Solicitações (pedido de 21/10/2026).
--
-- * Responder: no Chat e nas Solicitações, a mensagem nova pode citar uma anterior da mesma conversa (responde = id;
--   responde_texto e responde_de_nome guardam o trecho citado, para aparecer mesmo se a original sumir da tela).
-- * Número: cada solicitação enviada por quem pede ganha o número dela na conversa (1, 2, 3…); as respostas do
--   Nicolas não são numeradas. As antigas foram numeradas pela ordem de envio.
-- * Reagir com 👍 ou 👎: agora também nas Solicitações (as duas pontas da conversa).
-- Gravação só pelas funções (ninguém grava direto na tabela). chat_enviar e sol_enviar continuam (apps antigos) e
-- passam pelas funções novas chat_enviar2 e sol_enviar2, que aceitam a mensagem respondida.

alter table public.chat_msgs add column if not exists responde bigint;
alter table public.chat_msgs add column if not exists responde_texto text;
alter table public.chat_msgs add column if not exists responde_de_nome text;
alter table public.chat_msgs add column if not exists numero integer;

-- solicitações antigas: numeradas pela ordem em cada conversa
update public.chat_msgs m set numero = t.n
  from (select id, row_number() over (partition by conversa order by id) as n from public.chat_msgs where tipo = 'sol' and de <> 'mestre') t
 where m.id = t.id and m.numero is null;

-- trecho citado de uma mensagem da mesma conversa (nulo se não for da conversa)
create or replace function public.chat_citar_0027(p_responde bigint, p_tipo text, p_conversa text)
returns public.chat_msgs
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select * from public.chat_msgs m where m.id = p_responde and m.tipo = p_tipo and m.conversa = p_conversa limit 1; $$;
revoke execute on function public.chat_citar_0027(bigint, text, text) from public, anon, authenticated;

create or replace function public.chat_enviar2(p_para text, p_texto text, p_responde bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  v_conv text;
  c public.chat_msgs;
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  if p_para is null or p_para = v_eu or not public.chat_destino_ok_0019(p_para) then raise exception 'destino' using errcode = '22023'; end if;
  perform public.chat_limite_0019();
  v_conv := least(v_eu, p_para) || '|' || greatest(v_eu, p_para);
  if p_responde is not null then c := public.chat_citar_0027(p_responde, 'chat', v_conv); end if;
  insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto, responde, responde_texto, responde_de_nome)
  values ('chat', v_conv, v_eu, public.nome_atual(), p_para, v_txt, c.id,
          case when c.id is null then null when c.apagada then '(mensagem apagada)' else left(c.texto, 160) end, c.de_nome)
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.chat_enviar2(text, text, bigint) from public, anon;
grant execute on function public.chat_enviar2(text, text, bigint) to authenticated;

create or replace function public.sol_enviar2(p_texto text, p_conversa text default null, p_responde bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eu text := public.ref_atual();
  v_txt text := btrim(coalesce(p_texto, ''));
  v_conv text;
  v_num int;
  c public.chat_msgs;
  r public.chat_msgs;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if v_txt = '' or length(v_txt) > 2000 then raise exception 'texto' using errcode = '22023'; end if;
  perform public.chat_limite_0019();
  if v_eu = 'mestre' then
    if p_conversa is null or p_conversa = 'mestre' or not public.chat_destino_ok_0019(p_conversa) then raise exception 'destino' using errcode = '22023'; end if;
    v_conv := p_conversa;
  else
    v_conv := v_eu;
    perform pg_advisory_xact_lock(hashtext('sol|' || v_conv));
    select coalesce(max(numero), 0) + 1 into v_num from public.chat_msgs where tipo = 'sol' and conversa = v_conv and de <> 'mestre';
  end if;
  if p_responde is not null then c := public.chat_citar_0027(p_responde, 'sol', v_conv); end if;
  insert into public.chat_msgs (tipo, conversa, de, de_nome, para, texto, numero, responde, responde_texto, responde_de_nome)
  values ('sol', v_conv, v_eu, public.nome_atual(), case when v_eu = 'mestre' then v_conv else 'mestre' end, v_txt, v_num, c.id,
          case when c.id is null then null when c.apagada then '(mensagem apagada)' else left(c.texto, 160) end, c.de_nome)
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.sol_enviar2(text, text, bigint) from public, anon;
grant execute on function public.sol_enviar2(text, text, bigint) to authenticated;

-- as funções antigas passam pelas novas (sem resposta)
create or replace function public.chat_enviar(p_para text, p_texto text)
returns jsonb language sql security definer set search_path = public, pg_temp
as $$ select public.chat_enviar2(p_para, p_texto, null); $$;
create or replace function public.sol_enviar(p_texto text, p_conversa text default null)
returns jsonb language sql security definer set search_path = public, pg_temp
as $$ select public.sol_enviar2(p_texto, p_conversa, null); $$;

-- reagir com 👍 ou 👎 (p_reacao nulo ou vazio tira a reação): Chat e Solicitações
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
  select * into r from public.chat_msgs m where m.id = p_id and m.tipo in ('chat', 'sol') and (m.de = v_eu or m.para = v_eu) for update;
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
