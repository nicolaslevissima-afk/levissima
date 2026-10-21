-- LEVÍSSIMA · 0029 (pedidos de 21/10/2026, módulo Manutenção)
--
-- * Apagar um chamado: só a senha mestre (Nicolas). Os outros acessos do módulo continuam cancelando (o registro fica).
--   A única exceção é o "Arquivar" das Configurações do módulo, que tira da lista ativa os chamados encerrados depois de
--   guardá-los no arquivo: o chamado só sai se já estiver encerrado e dentro de um pacote do arquivo.
-- * Documentação dos equipamentos: bucket privado "modulos-docs" (só PDF, até 30 MB), na pasta do módulo
--   (manutencao/equipamentos/...). Lê e envia quem usa o módulo; apaga só a senha mestre (como as fotos).

-- o chamado já está guardado num pacote do arquivo (e encerrado)?
create or replace function public.manut_chamado_arquivado_0029(p_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.modulo_docs c
     where c.modulo = 'manutencao' and c.caminho = 'chamados' and c.id = p_id
       and c.dados ->> 'status' in ('concluido', 'cancelado'))
     and exists (
    select 1 from public.modulo_docs a
     where a.modulo = 'manutencao' and a.caminho = 'arquivo' and a.dados ->> 'tipo' = 'os'
       and a.dados -> 'itens' @> jsonb_build_array(jsonb_build_object('id', p_id)));
$$;
revoke execute on function public.manut_chamado_arquivado_0029(text) from public, anon;
grant execute on function public.manut_chamado_arquivado_0029(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'modulo_docs' and policyname = 'manut_chamado_so_mestre_apaga_0029') then
    create policy "manut_chamado_so_mestre_apaga_0029" on public.modulo_docs as restrictive for delete to authenticated
      using (not (modulo = 'manutencao' and caminho = 'chamados')
             or (select public.ref_atual()) = 'mestre'
             or public.manut_chamado_arquivado_0029(id));
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('modulos-docs', 'modulos-docs', false, 31457280, array['application/pdf'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-docs: quem usa o modulo le') then
    create policy "modulos-docs: quem usa o modulo le" on storage.objects for select to authenticated
      using (bucket_id = 'modulos-docs' and public.pode_modulo(split_part(name, '/', 1)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-docs: quem usa o modulo envia') then
    create policy "modulos-docs: quem usa o modulo envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'modulos-docs' and public.pode_modulo(split_part(name, '/', 1)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-docs: mestre apaga') then
    create policy "modulos-docs: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'modulos-docs' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
