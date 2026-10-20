-- LEVÍSSIMA · 0022: fotos dos itens do pedido de compra (pedido de 19/10/2026).
-- Quem faz o pedido pode pôr, em cada item, um link da internet (sugestão de onde comprar) e até 3 fotos do produto.
-- As fotos ficam no bucket privado "compras", pasta compras/<OC>/; só o escritório (senha mestre, diretoria e equipe)
-- envia e vê; apagar, só a senha mestre.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('compras', 'compras', false, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras: escritorio envia') then
    create policy "compras: escritorio envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'compras' and (select public.papel_atual()) in ('mestre', 'equipe') and not (select public.so_ver())
                  and name ~ '^compras/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras: escritorio le') then
    create policy "compras: escritorio le" on storage.objects for select to authenticated
      using (bucket_id = 'compras' and (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras: mestre apaga') then
    create policy "compras: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'compras' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
