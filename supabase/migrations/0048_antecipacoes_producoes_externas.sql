-- LEVÍSSIMA · 0048: antecipações de compras e produções externas (pedidos de 10/11/2026).
--
-- 1. ANTECIPAÇÕES DE COMPRAS. Coleção "compras-antecipacoes" (tabela docs): insumo faturado antes da entrega. Cada
--    documento guarda a nota (fornecedor, nº, data, valor, previsão de entrega), os itens faturados e as entregas
--    conferidas ("entregas": data, o que chegou, confere ou tem divergência, quem conferiu), até zerar o saldo.
--    Quem vê e lança: a senha mestre e a diretoria, e a pessoa do escritório (acesso pessoal) com "Vê a aba
--    Antecipações de compras", "Compras" ou "Aprova compra" em Cadastros › Equipe. Só a senha mestre apaga (o app
--    nunca apaga: lançamento errado é cancelado com o motivo).
-- 2. PRODUÇÕES EXTERNAS. Produto feito em outra fonte (Fonte Atibaia, Fonte Pedra Bela). Coleções:
--      prodext-config     um documento por fonte: nomes, valor combinado, insumos usados por fardo, itens a mais
--      prodext-movs       lançamentos: produção, transferência, saída, perda, contagem; envio, retorno e consumo de
--                         insumos. Cada um guarda os "efeitos" (item, local "fonte" ou "unidade", quantidade)
--      prodext-cobrancas  notas cobradas pela fonte: itens, valor cobrado × combinado, conferência e pagamento
--      prodext-laudos     laudos e documentos da fonte, com validade
--    Quem vê e lança: a senha mestre e a diretoria, e a pessoa do escritório (acesso pessoal) com "Vê a aba Produções
--    externas" em Cadastros › Equipe. Só a senha mestre apaga.
-- 3. ARQUIVOS. Bucket PRIVADO "compras-docs" (até 15 MB, PDF e fotos): "antecipacoes/<id>/<arquivo>" (nota fiscal) e
--    "producoes-externas/<fonte>/<arquivo>" (notas e laudos). Cada pasta segue a regra da sua aba; só a senha mestre
--    apaga.

create or replace function public.antecip_pode_0048()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); m jsonb;
begin
  if coalesce(public.papel_atual(), '') = 'mestre' then return true; end if;
  if coalesce(public.papel_atual(), '') <> 'equipe' or r not like 'escritorio:%' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  if m is null then return false; end if;
  return coalesce(m -> 'veAntecipacoes' = 'true'::jsonb, false) or coalesce(m -> 'compras' = 'true'::jsonb, false)
      or coalesce(m -> 'aprovaCompra' = 'true'::jsonb, false);
end $$;
revoke execute on function public.antecip_pode_0048() from public, anon;
grant execute on function public.antecip_pode_0048() to authenticated;

create or replace function public.prodext_pode_0048()
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); m jsonb;
begin
  if coalesce(public.papel_atual(), '') = 'mestre' then return true; end if;
  if coalesce(public.papel_atual(), '') <> 'equipe' or r not like 'escritorio:%' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  return coalesce(m -> 'veProdExternas' = 'true'::jsonb, false);
end $$;
revoke execute on function public.prodext_pode_0048() from public, anon;
grant execute on function public.prodext_pode_0048() to authenticated;

create or replace function public.colecao_prodext_0048(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp
as $$ select p_colecao in ('prodext-config', 'prodext-movs', 'prodext-cobrancas', 'prodext-laudos'); $$;
revoke execute on function public.colecao_prodext_0048(text) from public, anon;
grant execute on function public.colecao_prodext_0048(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'antecipacoes_0048') then
    create policy "antecipacoes_0048" on public.docs as restrictive for all to authenticated
      using (colecao <> 'compras-antecipacoes' or (select public.antecip_pode_0048()))
      with check (colecao <> 'compras-antecipacoes' or (select public.antecip_pode_0048()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'antecipacoes_apaga_0048') then
    create policy "antecipacoes_apaga_0048" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'compras-antecipacoes' or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'prodext_0048') then
    create policy "prodext_0048" on public.docs as restrictive for all to authenticated
      using (not public.colecao_prodext_0048(colecao) or (select public.prodext_pode_0048()))
      with check (not public.colecao_prodext_0048(colecao) or (select public.prodext_pode_0048()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'prodext_apaga_0048') then
    create policy "prodext_apaga_0048" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_prodext_0048(colecao) or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('compras-docs', 'compras-docs', false, 15728640,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras-docs: envia') then
    create policy "compras-docs: envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'compras-docs' and (
        (name ~ '^antecipacoes/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$' and (select public.antecip_pode_0048()))
        or (name ~ '^producoes-externas/[A-Za-z0-9_-]{1,60}/[A-Za-z0-9_.-]{1,120}$' and (select public.prodext_pode_0048()))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras-docs: le') then
    create policy "compras-docs: le" on storage.objects for select to authenticated
      using (bucket_id = 'compras-docs' and (
        (name like 'antecipacoes/%' and (select public.antecip_pode_0048()))
        or (name like 'producoes-externas/%' and (select public.prodext_pode_0048()))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'compras-docs: mestre apaga') then
    create policy "compras-docs: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'compras-docs' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
