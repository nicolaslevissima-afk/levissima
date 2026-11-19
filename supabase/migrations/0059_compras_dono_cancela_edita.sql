-- LEVÍSSIMA · 0059: Compras — quem fez o pedido cancela e edita o próprio pedido, mesmo com "só inclui", com motivo
-- (pedido de 19/11/2026, tarde).
--
-- A 0058 deixou o acesso da equipe com todas as abas "só inclui" (so_inclui) assinar as etapas da ordem de compra, mas
-- continuou barrando editar o pedido e cancelar. Agora, quem fez o pedido (pedido.ref = o acesso de quem grava, ou o
-- mesmo cadastro da equipe) pode, na própria ordem:
--   * cancelar, com o motivo (cancelamento.motivo, 3 letras ou mais);
--   * editar itens, setor, urgência e observação, com o motivo da alteração (edicao.motivo, 3 letras ou mais).
-- Continua barrado para ele: mudar quem pediu, o número e a data do pedido. A regra da 0043 continua valendo para
-- todos: depois da cotação, itens, setor, urgência e observação não mudam; cancelar só até a aprovação da diretoria
-- (conferido pelo app). Pedido de outra pessoa com "só inclui" continua só assinando as etapas (0058).
-- (Quem tem a aba Compras "só inclui" mas não todas as abas não recebe so_inclui: o banco já não barrava; o app
-- passou a liberar a mesma coisa para quem fez o pedido.)

create or replace function public.oc_so_inclui_0058()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
  v_r text;
  v_dono boolean;
begin
  if new.colecao <> 'compras-ordens' or tg_op <> 'UPDATE' then return new; end if;
  if auth.jwt() is null then return new; end if; -- manutenção direta no banco
  if not public.so_inclui() or coalesce(public.papel_atual(), '') <> 'equipe' then return new; end if;

  v_r := coalesce(public.ref_atual(), '');
  v_dono := v_r <> '' and (coalesce(old.data -> 'pedido' ->> 'ref', '') = v_r
    or (v_r like 'escritorio:%' and coalesce(old.data -> 'pedido' ->> 'id', '') = substr(v_r, 12)));

  if v_dono then
    foreach k in array array['pedido', 'numero', 'criadoEm'] loop
      if (new.data -> k) is distinct from (old.data -> k) then
        raise exception 'so_inclui' using errcode = '42501';
      end if;
    end loop;
    if coalesce(new.data ->> 'status', '') = 'cancelada' and coalesce(old.data ->> 'status', '') <> 'cancelada'
       and length(btrim(coalesce(new.data -> 'cancelamento' ->> 'motivo', ''))) < 3 then
      raise exception 'Escreva o motivo do cancelamento.';
    end if;
    if ((new.data -> 'itens') is distinct from (old.data -> 'itens') or (new.data -> 'setor') is distinct from (old.data -> 'setor')
        or (new.data -> 'urgencia') is distinct from (old.data -> 'urgencia') or (new.data -> 'obs') is distinct from (old.data -> 'obs'))
       and length(btrim(coalesce(new.data -> 'edicao' ->> 'motivo', ''))) < 3 then
      raise exception 'Escreva o motivo da alteração.';
    end if;
    return new;
  end if;

  foreach k in array array['itens', 'setor', 'urgencia', 'obs', 'pedido', 'numero', 'criadoEm', 'edicao', 'edicoes', 'cancelamento', 'canceladaEm', 'canceladaPor'] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'so_inclui' using errcode = '42501';
    end if;
  end loop;
  if coalesce(new.data ->> 'status', '') = 'cancelada' and coalesce(old.data ->> 'status', '') <> 'cancelada' then
    raise exception 'so_inclui' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function public.oc_so_inclui_0058() from public, anon, authenticated;
