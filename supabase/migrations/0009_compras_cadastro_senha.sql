-- LEVÍSSIMA · 0009: ordem de compra e pedido de senha com foto do documento e selfie.
--
-- Coleções novas na tabela "docs":
--   compras-ordens     ordens de compra (pedido → coordenador → cotação → Nicolas → entrega), com as assinaturas
--   cadastro-pedidos   pedido da senha de 4 números feito pela própria pessoa (CPF, fotos, senha só em hash)
--
-- Regras (somam com as que já existem; nenhuma regra antiga muda):
--   1. compras-ordens: só o escritório (senha mestre e equipe); só a senha mestre apaga;
--   2. cadastro-pedidos: só a senha mestre lê e decide; o pedido entra pela função cadastro_pedir, que confere
--      CPF, senha repetida e o cadastro do RH no servidor (escritório e setores da fábrica podem pedir);
--   3. bucket PRIVADO "cadastros" (fotos do documento e do rosto, até 15 MB): escritório e setores enviam;
--      só a senha mestre vê e apaga (o app apaga as fotos quando o pedido é decidido).

create or replace function public.colecao_escritorio_0009(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp
as $$ select p_colecao in ('compras-ordens'); $$;
revoke execute on function public.colecao_escritorio_0009(text) from public, anon;
grant execute on function public.colecao_escritorio_0009(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'escritorio_0009') then
    create policy "escritorio_0009" on public.docs as restrictive for all to authenticated
      using (not public.colecao_escritorio_0009(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (not public.colecao_escritorio_0009(colecao) or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'compras_apaga_0009') then
    create policy "compras_apaga_0009" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'compras-ordens' or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'cadastro_so_mestre_0009') then
    create policy "cadastro_so_mestre_0009" on public.docs as restrictive for all to authenticated
      using (colecao <> 'cadastro-pedidos' or (select public.papel_atual()) = 'mestre')
      with check (colecao <> 'cadastro-pedidos' or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

create or replace function public.sem_acento_0009(t text)
returns text language sql immutable set search_path = public, pg_temp
as $$ select lower(regexp_replace(btrim(translate(coalesce(t, ''), 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc')), '\s+', ' ', 'g')); $$;

-- Pedido da senha de 4 números (a senha chega só em hash). Erros: sem_permissao, nome, cpf, senha, senha_em_uso,
-- ja_pedido, fotos, aceite.
create or replace function public.cadastro_pedir(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  papel text := coalesce(public.papel_atual(), '');
  v_cpf text := regexp_replace(coalesce(p ->> 'cpf', ''), '\D', '', 'g');
  v_nome text := btrim(regexp_replace(coalesce(p ->> 'nome', ''), '\s+', ' ', 'g'));
  v_mat text := btrim(coalesce(p ->> 'matricula', ''));
  v_pin text := lower(coalesce(p ->> 'pinHash', ''));
  v_rh_id text; v_rh jsonb;
  v_id text;
  soma int; d1 int; d2 int; i int;
begin
  if papel not in ('mestre', 'equipe', 'setor') then raise exception 'sem_permissao'; end if;
  if length(v_nome) < 5 or position(' ' in v_nome) = 0 then raise exception 'nome'; end if;
  if length(v_cpf) <> 11 or v_cpf ~ '^(\d)\1{10}$' then raise exception 'cpf'; end if;
  soma := 0; for i in 1..9 loop soma := soma + substr(v_cpf, i, 1)::int * (11 - i); end loop;
  d1 := (soma * 10) % 11; if d1 = 10 then d1 := 0; end if;
  soma := 0; for i in 1..10 loop soma := soma + substr(v_cpf, i, 1)::int * (12 - i); end loop;
  d2 := (soma * 10) % 11; if d2 = 10 then d2 := 0; end if;
  if d1 <> substr(v_cpf, 10, 1)::int or d2 <> substr(v_cpf, 11, 1)::int then raise exception 'cpf'; end if;
  if v_pin !~ '^[0-9a-f]{64}$' then raise exception 'senha'; end if;
  if exists (select 1 from public.docs where colecao = 'equipe' and lower(data ->> 'pinHash') = v_pin
             and public.sem_acento_0009(data ->> 'nome') <> public.sem_acento_0009(v_nome)) then raise exception 'senha_em_uso'; end if;
  if exists (select 1 from public.docs where colecao = 'cadastro-pedidos' and data ->> 'status' = 'pendente' and data ->> 'cpf' = v_cpf) then raise exception 'ja_pedido'; end if;
  if coalesce(p ->> 'fotoDoc', '') !~ '^pedidos/' or coalesce(p ->> 'fotoRosto', '') !~ '^pedidos/' then raise exception 'fotos'; end if;
  if coalesce((p ->> 'aceite')::boolean, false) is not true then raise exception 'aceite'; end if;
  -- confere no cadastro do RH (módulo Uniformes): pela matrícula ou pelo nome
  select m.id, m.dados into v_rh_id, v_rh from public.modulo_docs m
   where m.modulo = 'uniformes' and m.caminho = 'funcionarios'
     and ((v_mat <> '' and m.dados ->> 'matricula' = v_mat) or public.sem_acento_0009(m.dados ->> 'nome') = public.sem_acento_0009(v_nome))
   order by (v_mat <> '' and m.dados ->> 'matricula' = v_mat) desc limit 1;
  v_id := 'cp' || to_char(now(), 'YYYYMMDDHH24MISS') || substr(md5(random()::text), 1, 6);
  insert into public.docs (colecao, id, data) values ('cadastro-pedidos', v_id, jsonb_build_object(
    'status', 'pendente', 'nome', v_nome, 'matricula', v_mat, 'cpf', v_cpf, 'pinHash', v_pin,
    'fotoDoc', p ->> 'fotoDoc', 'fotoRosto', p ->> 'fotoRosto', 'aceite', true, 'aceiteTexto', left(coalesce(p ->> 'aceiteTexto', ''), 400),
    'rh', case when v_rh_id is null then null else jsonb_build_object('id', v_rh_id, 'nome', v_rh ->> 'nome', 'matricula', v_rh ->> 'matricula',
      'funcao', v_rh ->> 'funcao', 'setor', v_rh ->> 'setor', 'admissao', v_rh ->> 'admissao') end,
    'pedidoPor', papel, 'criadoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  return jsonb_build_object('ok', true, 'id', v_id, 'rh', v_rh_id is not null);
end $$;
revoke execute on function public.cadastro_pedir(jsonb) from public, anon;
grant execute on function public.cadastro_pedir(jsonb) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cadastros', 'cadastros', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'cadastros: envia') then
    create policy "cadastros: envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'cadastros' and (select public.papel_atual()) in ('mestre', 'equipe', 'setor') and name like 'pedidos/%');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'cadastros: mestre le') then
    create policy "cadastros: mestre le" on storage.objects for select to authenticated
      using (bucket_id = 'cadastros' and (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'cadastros: mestre apaga') then
    create policy "cadastros: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'cadastros' and (select public.papel_atual()) = 'mestre');
  end if;
end $$;
