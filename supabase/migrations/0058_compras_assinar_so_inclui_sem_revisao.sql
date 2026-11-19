-- LEVÍSSIMA · 0058: Compras — assinar as etapas com "só inclui" e sem a conferência da cotação por quem pediu
-- (pedidos de 19/11/2026).
--
-- 1. Quem tem todas as abas "só inclui" recebe so_inclui no login (0021) e o banco recusava qualquer alteração (0014):
--    essa pessoa não conseguia assinar nenhuma etapa da ordem de compra, nem confirmar a entrega do próprio pedido.
--    Agora, na coleção compras-ordens, o acesso da equipe (papel 'equipe') com so_inclui pode gravar a assinatura das
--    etapas. Continua barrado para ele: mudar o pedido (itens, setor, urgência, observação, quem pediu, número,
--    alterações) e cancelar a ordem. A diretoria (papel 'mestre' com so_inclui) e o "só visualiza" não mudam.
--    Quem assina cada etapa continua sendo conferido pelo app (cargo, senha de 4 números ou o próprio acesso), como
--    já era para quem tem a aba "Edita".
-- 2. A etapa "Quem pediu confere a cotação" (0046) saiu: a cotação vai direto para a diretoria. Ordem que ainda
--    estiver nessa etapa passa para "Aguardando diretoria".

alter policy "so_inclui_nao_altera_0014" on public.docs
  using (not (select public.so_inclui()) or (colecao = 'compras-ordens' and (select public.papel_atual()) = 'equipe'))
  with check (not (select public.so_inclui()) or (colecao = 'compras-ordens' and (select public.papel_atual()) = 'equipe'));

create or replace function public.oc_so_inclui_0058()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
begin
  if new.colecao <> 'compras-ordens' or tg_op <> 'UPDATE' then return new; end if;
  if auth.jwt() is null then return new; end if; -- manutenção direta no banco
  if not public.so_inclui() or coalesce(public.papel_atual(), '') <> 'equipe' then return new; end if;
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

create or replace trigger docs_oc_so_inclui_0058 before update on public.docs
  for each row when (new.colecao = 'compras-ordens') execute function public.oc_so_inclui_0058();

-- ordens que ainda esperavam quem pediu conferir a cotação: seguem para a diretoria
update public.docs
   set data = data || jsonb_build_object('status', 'aprovacao', 'atualizadoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
       atualizado_em = now()
 where colecao = 'compras-ordens' and data ->> 'status' = 'revisao';
