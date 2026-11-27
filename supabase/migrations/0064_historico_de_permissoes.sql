-- LEVÍSSIMA · 0064: histórico das mudanças de permissão (pedido de 26/11/2026, Painel de permissões em Cadastros).
-- * Coleção permissoes-historico (docs): cada mudança de permissão feita pelo painel, pelo perfil da pessoa ou em
--   Acesso ao app (quem mudou, de quem, o quê, de → para, quando).
-- * Só a senha mestre (e a diretoria, que entra com o papel da senha mestre) lê e grava (colecao_so_mestre).
-- * Ninguém altera nem apaga um registro, nem a senha mestre; quem grava fica carimbado pelo login (porRef).

create or replace function public.colecao_so_mestre(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_colecao in ('motorista-docs', 'representantes', 'representante-docs', 'permissoes-historico');
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'permissoes_historico_grava_0064') then
    create policy "permissoes_historico_grava_0064" on public.docs as restrictive for insert to authenticated
      with check (colecao <> 'permissoes-historico' or coalesce(data ->> 'porRef', '') = (select public.ref_atual()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'permissoes_historico_fixo_0064') then
    create policy "permissoes_historico_fixo_0064" on public.docs as restrictive for update to authenticated
      using (colecao <> 'permissoes-historico');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'permissoes_historico_nao_apaga_0064') then
    create policy "permissoes_historico_nao_apaga_0064" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'permissoes-historico');
  end if;
end $$;
