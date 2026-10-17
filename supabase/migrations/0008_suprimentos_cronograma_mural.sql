-- LEVÍSSIMA · 0008: cronograma de saída, fornecedores, laudos, cronograma de recebimento da matéria-prima
-- e recado em destaque.
--
-- Coleções novas na tabela "docs":
--   saidas-programadas   cronograma de saída por marca e período, em paletes (entra no saldo futuro do Estoque)
--   fornecedores         cadastro dos fornecedores (insumos que entregam, prazo, situação)
--   fornecedores-laudos  laudos e documentos dos fornecedores, com validade (arquivo no bucket "fornecedores-laudos")
--   mp-agendamentos      entregas de matéria-prima: agendamento, chegada, conferência da carga e inspeção
--   mural                recado em destaque (doc "atual"), que aparece para todos os acessos
--
-- Regras (somam com as que já existem; nenhuma regra antiga muda):
--   1. as quatro primeiras são só do escritório: senha mestre e senha da equipe;
--   2. fornecedores e laudos: a equipe cadastra e edita; só a senha mestre apaga;
--   3. mural: todos os acessos leem (escritório, motoristas, força de vendas e setores); só a senha mestre grava.
-- Arquivos dos laudos: bucket PRIVADO "fornecedores-laudos" (até 15 MB, PDF e fotos); o escritório lê e envia,
-- só a senha mestre apaga.

create or replace function public.colecao_escritorio_0008(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('saidas-programadas', 'fornecedores', 'fornecedores-laudos', 'mp-agendamentos'); $$;
revoke execute on function public.colecao_escritorio_0008(text) from public, anon;
grant execute on function public.colecao_escritorio_0008(text) to authenticated;

create or replace function public.colecao_apaga_mestre_0008(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('fornecedores', 'fornecedores-laudos'); $$;
revoke execute on function public.colecao_apaga_mestre_0008(text) from public, anon;
grant execute on function public.colecao_apaga_mestre_0008(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'escritorio_0008') then
    create policy "escritorio_0008" on public.docs as restrictive for all to authenticated
      using (not public.colecao_escritorio_0008(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_escritorio_0008(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mestre_apaga_0008') then
    create policy "mestre_apaga_0008" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_apaga_mestre_0008(colecao) or (select public.papel_atual()) = 'mestre');
  end if;
  -- mural: leitura para todos os acessos
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mural_le_0008') then
    create policy "mural_le_0008" on public.docs for select to authenticated
      using (colecao = 'mural');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mural_grava_0008') then
    create policy "mural_grava_0008" on public.docs as restrictive for insert to authenticated
      with check (colecao <> 'mural' or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mural_altera_0008') then
    create policy "mural_altera_0008" on public.docs as restrictive for update to authenticated
      using (colecao <> 'mural' or (select public.papel_atual()) = 'mestre')
      with check (colecao <> 'mural' or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mural_apaga_0008') then
    create policy "mural_apaga_0008" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'mural' or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fornecedores-laudos', 'fornecedores-laudos', false, 15728640,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fornecedores-laudos: escritorio le') then
    create policy "fornecedores-laudos: escritorio le" on storage.objects for select to authenticated
      using (bucket_id = 'fornecedores-laudos' and (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fornecedores-laudos: escritorio envia') then
    create policy "fornecedores-laudos: escritorio envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'fornecedores-laudos' and (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'fornecedores-laudos: mestre apaga') then
    create policy "fornecedores-laudos: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'fornecedores-laudos' and (select public.papel_atual()) = 'mestre');
  end if;
end $$;
