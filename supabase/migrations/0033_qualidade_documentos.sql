-- LEVÍSSIMA · 0033: gestão de documentos da Qualidade (pedido de 26/10/2026).
--
-- * Coleções (tabela docs): qualidade-documentos (um por documento: versão vigente, revisão em andamento, histórico
--   de versões e cópias controladas) e qualidade-doc-leituras (quem confirmou a leitura de cada versão).
-- * Só quem tem a aba Qualidade lê e grava: senha mestre (e diretoria) e, na equipe, quem tem a aba marcada no acesso
--   (ou a senha geral da equipe, que abre todas as abas). "Só visualiza" não grava. Ninguém apaga, só a senha mestre:
--   versão antiga vira histórico e documento cancelado fica obsoleto.
-- * Arquivos no balde privado qualidade-docs (até 30 MB): lê e envia quem tem a aba Qualidade; ninguém altera nem
--   apaga (só a senha mestre apaga).

create or replace function public.ve_aba_0033(p_aba text)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'mestre'
      or (coalesce(auth.jwt() -> 'app_metadata' ->> 'papel', '') = 'equipe'
          and (not coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? 'abas', false)
               or coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ? ('aba:' || p_aba), false)));
$$;
revoke execute on function public.ve_aba_0033(text) from public, anon;
grant execute on function public.ve_aba_0033(text) to authenticated;

create or replace function public.colecao_documentos_0033(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('qualidade-documentos', 'qualidade-doc-leituras'); $$;
revoke execute on function public.colecao_documentos_0033(text) from public, anon;
grant execute on function public.colecao_documentos_0033(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_documentos_le_0033') then
    create policy "qualidade_documentos_le_0033" on public.docs as restrictive for select to authenticated
      using (not public.colecao_documentos_0033(colecao) or (select public.ve_aba_0033('qualidade')));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_documentos_grava_0033') then
    create policy "qualidade_documentos_grava_0033" on public.docs as restrictive for insert to authenticated
      with check (not public.colecao_documentos_0033(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver())));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_documentos_altera_0033') then
    create policy "qualidade_documentos_altera_0033" on public.docs as restrictive for update to authenticated
      using (not public.colecao_documentos_0033(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver()) and (colecao <> 'qualidade-doc-leituras' or (select public.papel_atual()) = 'mestre')))
      with check (not public.colecao_documentos_0033(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver()) and (colecao <> 'qualidade-doc-leituras' or (select public.papel_atual()) = 'mestre')));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_documentos_apaga_0033') then
    create policy "qualidade_documentos_apaga_0033" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_documentos_0033(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('qualidade-docs', 'qualidade-docs', false, 31457280, array[
  'application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'text/plain', 'text/csv', 'application/zip', 'application/octet-stream'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'qualidade-docs: le 0033') then
    create policy "qualidade-docs: le 0033" on storage.objects for select to authenticated
      using (bucket_id = 'qualidade-docs' and (select public.ve_aba_0033('qualidade')));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'qualidade-docs: envia 0033') then
    create policy "qualidade-docs: envia 0033" on storage.objects for insert to authenticated
      with check (bucket_id = 'qualidade-docs' and (select public.ve_aba_0033('qualidade')) and not (select public.so_ver()) and name like 'doc/%');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'qualidade-docs: apaga 0033') then
    create policy "qualidade-docs: apaga 0033" on storage.objects for delete to authenticated
      using (bucket_id = 'qualidade-docs' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
