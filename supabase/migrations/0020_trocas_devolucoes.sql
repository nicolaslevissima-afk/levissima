-- LEVÍSSIMA · 0020: Trocas e devoluções (pedido de 19/10/2026).
-- A expedição lança o que voltou (qualquer produto: quem recebeu, cliente que devolveu, produto e quantidade e até
-- 5 fotos) e a Qualidade anota o destino do produto. Registros na coleção "trocas" da tabela docs; fotos no bucket
-- privado "trocas", pasta trocas/<registro>/.
-- Só o escritório (senha mestre, diretoria e equipe) lê e grava; apagar, só a senha mestre.

create or replace function public.colecao_escritorio_0020(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('trocas'); $$;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'escritorio_0020') then
    create policy escritorio_0020 on public.docs as restrictive for all to authenticated
      using (not public.colecao_escritorio_0020(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_escritorio_0020(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'trocas_apaga_0020') then
    create policy trocas_apaga_0020 on public.docs as restrictive for delete to authenticated
      using (not public.colecao_escritorio_0020(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('trocas', 'trocas', false, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'trocas: escritorio envia') then
    create policy "trocas: escritorio envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'trocas' and (select public.papel_atual()) in ('mestre', 'equipe')
                  and name ~ '^trocas/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'trocas: escritorio le') then
    create policy "trocas: escritorio le" on storage.objects for select to authenticated
      using (bucket_id = 'trocas' and (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'trocas: mestre apaga') then
    create policy "trocas: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'trocas' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
