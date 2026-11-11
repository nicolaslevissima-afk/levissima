-- LEVÍSSIMA · 0049: Qualidade › Laboratório, etapa 1 (pedido de 11/11/2026; POP 013 – Plano de Amostragem, rev. 02).
--
-- Coleções (tabela docs):
--   lab-config     documento "plano": parâmetros, limites físico-químicos por fonte, controles e frequências, pontos
--                  de coleta, linhas, pontos do POP a confirmar e o histórico de alterações do plano.
--   lab-registros  cada coleta/análise: identificação (lote = produto + data de produção + linha, ou ponto,
--                  colaborador, cabeçote), resultados com o critério usado, lançamento, validação, decisão do lote,
--                  anexos e histórico.
-- Só o escritório (senha mestre, diretoria e equipe) lê e grava; só a senha mestre (sem "só inclui") apaga.
-- O gatilho lab_registro_guarda_0049 protege o registro:
--   * não nasce validado;
--   * resultado já lançado só muda se o histórico crescer junto (o app grava o valor antigo e o motivo) e a
--     validação sair (volta a pedir validação);
--   * o histórico e a lista de quem lançou nunca encolhem;
--   * quem valida não pode estar entre quem lançou ou corrigiu (lancadoPor).
-- Bucket privado "laboratorio" (15 MB, PDF e fotos): registros/<id>/<arquivo>; escritório envia e lê; só a senha
-- mestre apaga.

create or replace function public.lab_registro_guarda_0049()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
  o jsonb;
  n jsonb;
  mudou boolean := false;
  h_old int;
  h_new int;
  vid text;
begin
  if new.colecao <> 'lab-registros' then return new; end if;
  if tg_op = 'INSERT' then
    if jsonb_typeof(new.data -> 'validacao') = 'object' then
      raise exception 'laboratorio: registro novo não pode chegar validado' using errcode = '42501';
    end if;
    return new;
  end if;
  -- resultados já lançados (com valor) que mudaram
  for k, o in select key, value from jsonb_each(case when jsonb_typeof(old.data -> 'resultados') = 'object' then old.data -> 'resultados' else '{}'::jsonb end) loop
    if coalesce(o ->> 'v', '') <> '' or coalesce(o ->> 't', '') <> '' then
      n := new.data -> 'resultados' -> k;
      if n is null or coalesce(n ->> 'v', '') <> coalesce(o ->> 'v', '') or coalesce(n ->> 't', '') <> coalesce(o ->> 't', '') or coalesce(n ->> 'a', '') <> coalesce(o ->> 'a', '') then
        mudou := true;
      end if;
    end if;
  end loop;
  h_old := case when jsonb_typeof(old.data -> 'historico') = 'array' then jsonb_array_length(old.data -> 'historico') else 0 end;
  h_new := case when jsonb_typeof(new.data -> 'historico') = 'array' then jsonb_array_length(new.data -> 'historico') else 0 end;
  if h_new < h_old then
    raise exception 'laboratorio: o histórico não pode ser apagado' using errcode = '42501';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(old.data -> 'lancadoPor') = 'array' then old.data -> 'lancadoPor' else '[]'::jsonb end) x
             where not (coalesce(new.data -> 'lancadoPor', '[]'::jsonb) ? x)) then
    raise exception 'laboratorio: a lista de quem lançou não pode encolher' using errcode = '42501';
  end if;
  if mudou then
    if h_new <= h_old then
      raise exception 'laboratorio: resultado alterado sem registro no histórico' using errcode = '42501';
    end if;
    if jsonb_typeof(new.data -> 'validacao') = 'object' then
      raise exception 'laboratorio: resultado alterado precisa de nova validação' using errcode = '42501';
    end if;
  end if;
  -- validação nova: quem valida não lançou nem corrigiu
  if jsonb_typeof(new.data -> 'validacao') = 'object' and (jsonb_typeof(old.data -> 'validacao') is distinct from 'object' or (old.data -> 'validacao' ->> 'porId') is distinct from (new.data -> 'validacao' ->> 'porId')) then
    vid := coalesce(new.data -> 'validacao' ->> 'porId', '');
    if vid = '' or coalesce(new.data -> 'lancadoPor', '[]'::jsonb) ? vid then
      raise exception 'laboratorio: quem lançou não valida o próprio resultado' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.lab_registro_guarda_0049() from public, anon, authenticated;

drop trigger if exists lab_registro_guarda_0049 on public.docs;
create trigger lab_registro_guarda_0049 before insert or update on public.docs
  for each row when (new.colecao = 'lab-registros') execute function public.lab_registro_guarda_0049();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'lab_0049') then
    create policy "lab_0049" on public.docs as restrictive for all to authenticated
      using (colecao not in ('lab-registros', 'lab-config') or (select public.papel_atual()) in ('mestre', 'equipe'))
      with check (colecao not in ('lab-registros', 'lab-config') or (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'lab_apaga_0049') then
    create policy "lab_apaga_0049" on public.docs as restrictive for delete to authenticated
      using (colecao not in ('lab-registros', 'lab-config') or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('laboratorio', 'laboratorio', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'laboratorio: envia') then
    create policy "laboratorio: envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'laboratorio' and (select public.papel_atual()) in ('mestre', 'equipe')
                  and name ~ '^registros/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'laboratorio: le') then
    create policy "laboratorio: le" on storage.objects for select to authenticated
      using (bucket_id = 'laboratorio' and (select public.papel_atual()) in ('mestre', 'equipe'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'laboratorio: mestre apaga') then
    create policy "laboratorio: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'laboratorio' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
