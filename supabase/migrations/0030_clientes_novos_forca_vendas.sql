-- LEVÍSSIMA · 0030 (pedido de 21/10/2026): Força de vendas — cliente novo em análise
--
-- O representante cadastra o cliente novo (coleção "clientes-novos", com a ref dele em representanteRef) e só vê os
-- dele; o pedido entra com status "analise", sem aprovações. O escritório (senha mestre e equipe) vê todos e grava
-- as aprovações do Leonardo (comercial) e do financeiro. Motoristas e setores não veem nada desta coleção.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'clientes_novos_rep_le_0030') then
    create policy "clientes_novos_rep_le_0030" on public.docs for select to authenticated
      using (colecao = 'clientes-novos' and (select public.papel_atual()) = 'representante' and data ->> 'representanteRef' = (select public.ref_atual()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'clientes_novos_rep_grava_0030') then
    create policy "clientes_novos_rep_grava_0030" on public.docs for insert to authenticated
      with check (colecao = 'clientes-novos' and (select public.papel_atual()) = 'representante' and data ->> 'representanteRef' = (select public.ref_atual())
                  and data ->> 'status' = 'analise' and not (data ? 'comercial') and not (data ? 'financeiro'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'clientes_novos_quem_0030') then
    create policy "clientes_novos_quem_0030" on public.docs as restrictive for all to authenticated
      using (colecao <> 'clientes-novos' or (select public.papel_atual()) in ('mestre', 'equipe')
             or ((select public.papel_atual()) = 'representante' and data ->> 'representanteRef' = (select public.ref_atual())))
      with check (colecao <> 'clientes-novos' or (select public.papel_atual()) in ('mestre', 'equipe')
             or ((select public.papel_atual()) = 'representante' and data ->> 'representanteRef' = (select public.ref_atual()) and data ->> 'status' = 'analise'));
  end if;
end $$;
