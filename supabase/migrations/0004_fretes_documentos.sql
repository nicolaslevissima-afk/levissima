-- LEVÍSSIMA · 0004: fretes dos motoristas e documentos do motorista e do caminhão.
--
-- Coleções novas na tabela "docs" que SÓ a senha mestre lê e grava:
--   fretes-tabela   a tabela de fretes, com os valores (doc "atual")
--   fretes          o frete de cada carga: valor confirmado, ajuste e pagamento (id = id da carga)
--   motorista-docs  a lista de documentos de cada motorista e do caminhão (os arquivos ficam no Storage)
-- O nome dos destinos, sem valores, fica em config/fretes-destinos: a equipe usa ao lançar a carga.
--
-- Não mexe nas regras que já existem: acrescenta uma regra RESTRITIVA (vale junto com as outras, em
-- toda leitura e gravação) que barra essas coleções para quem não é a senha mestre.
--
-- Arquivos dos documentos: bucket PRIVADO "motoristas-docs" no Storage, também só para a senha mestre
-- (até 15 MB por arquivo; fotos e PDF).

create or replace function public.colecao_so_mestre(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('fretes', 'fretes-tabela', 'motorista-docs'); $$;
revoke execute on function public.colecao_so_mestre(text) from public, anon;
grant execute on function public.colecao_so_mestre(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_mestre') then
    create policy "so_mestre" on public.docs as restrictive for all to authenticated
      using (not public.colecao_so_mestre(colecao) or (select public.papel_atual()) = 'mestre')
      with check (not public.colecao_so_mestre(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('motoristas-docs', 'motoristas-docs', false, 15728640,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'motoristas-docs: mestre le') then
    create policy "motoristas-docs: mestre le" on storage.objects for select to authenticated
      using (bucket_id = 'motoristas-docs' and (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'motoristas-docs: mestre envia') then
    create policy "motoristas-docs: mestre envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'motoristas-docs' and (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'motoristas-docs: mestre altera') then
    create policy "motoristas-docs: mestre altera" on storage.objects for update to authenticated
      using (bucket_id = 'motoristas-docs' and (select public.papel_atual()) = 'mestre')
      with check (bucket_id = 'motoristas-docs' and (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'motoristas-docs: mestre apaga') then
    create policy "motoristas-docs: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'motoristas-docs' and (select public.papel_atual()) = 'mestre');
  end if;
end $$;
