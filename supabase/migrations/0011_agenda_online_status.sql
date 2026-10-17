-- LEVÍSSIMA · 0011: confirmação e cancelamento do agendamento on-line sem corrida.
-- A função "agendamento" muda só os campos do status, num comando só (não regrava o documento inteiro) e nunca
-- confirma o que já foi cancelado. Só a chave de serviço (a própria função) pode chamar.
create or replace function public.agenda_online_mudar(p_id text, p_cliente text, p_acao text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  n int;
  agora text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if p_acao = 'confirmar' then
    update public.docs set data = data || jsonb_build_object('status', 'confirmado', 'confirmadoEm', agora), atualizado_em = now()
     where colecao = 'agenda-itens' and id = p_id and data ->> 'clienteOnlineId' = p_cliente and coalesce((data ->> 'cancelado')::boolean, false) = false;
  elsif p_acao = 'cancelar' then
    update public.docs set data = data || jsonb_build_object('status', 'cancelado', 'cancelado', true, 'canceladoEm', agora, 'canceladoPor', 'cliente'), atualizado_em = now()
     where colecao = 'agenda-itens' and id = p_id and data ->> 'clienteOnlineId' = p_cliente and coalesce((data ->> 'cancelado')::boolean, false) = false;
  else
    raise exception 'acao';
  end if;
  get diagnostics n = row_count;
  return case when n = 1 then 'ok' else 'nada' end;
end $$;
revoke execute on function public.agenda_online_mudar(text, text, text) from public, anon, authenticated;
grant execute on function public.agenda_online_mudar(text, text, text) to service_role;
