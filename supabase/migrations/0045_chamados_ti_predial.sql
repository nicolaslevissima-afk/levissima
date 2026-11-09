-- LEVÍSSIMA · 0045: chamados para a TI e para a manutenção predial (pedido de 09/11/2026).
--
-- Coleção "chamados" (tabela docs), campo "area" = 'ti' ou 'predial'. Todos os usuários abrem chamado (senha mestre,
-- diretoria, escritório, senhas de setor da fábrica e motoristas); cada um vê os que abriu. Quem atende vê e mexe em
-- todos da área:
--   - senha mestre e diretoria (papel 'mestre');
--   - TI: pessoa do escritório marcada "Atende chamados de TI" (equipe.atendeTi) em Cadastros › Equipe;
--   - predial: pessoa marcada "Atende a manutenção predial" (equipe.atendePredial) ou quem gerencia o módulo
--     Manutenção (acesso com 'manutencao:gerir').
-- Gatilho docs_chamado_0045: ao abrir, o banco dá o número (sequência por área) e grava quem abriu pelo próprio login;
-- quem abriu (sem ser da equipe que atende) só comenta, cancela o chamado ainda aberto e confirma ou reabre o
-- resolvido. Só a senha mestre apaga. Fotos no bucket privado "chamados", pasta <área>/<chamado>/.

create or replace function public.chamado_atende_0045(p_area text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare p text := coalesce(public.papel_atual(), ''); r text := coalesce(public.ref_atual(), ''); m jsonb; mods jsonb;
begin
  if p = 'mestre' then return true; end if;
  if p not in ('equipe', 'setor') then return false; end if;
  mods := auth.jwt() -> 'app_metadata' -> 'modulos';
  if p_area = 'predial' and jsonb_typeof(mods) = 'array' and mods ? 'manutencao:gerir' then return true; end if;
  if p <> 'equipe' or r not like 'escritorio:%' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = substr(r, 12);
  if m is null then return false; end if;
  if p_area = 'ti' then return coalesce(m -> 'atendeTi' = 'true'::jsonb, false); end if;
  if p_area = 'predial' then return coalesce(m -> 'atendePredial' = 'true'::jsonb, false); end if;
  return false;
end $$;
revoke execute on function public.chamado_atende_0045(text) from public, anon;
grant execute on function public.chamado_atende_0045(text) to authenticated;

create or replace function public.chamado_visivel_0045(d jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), '');
begin
  if coalesce(public.papel_atual(), '') = '' then return false; end if;
  if public.chamado_atende_0045(d ->> 'area') then return true; end if;
  return r <> '' and coalesce(d -> 'solicitante' ->> 'ref', '') = r;
end $$;
revoke execute on function public.chamado_visivel_0045(jsonb) from public, anon;
grant execute on function public.chamado_visivel_0045(jsonb) to authenticated;

-- número, quem abriu e o que quem abriu pode mudar
create or replace function public.chamado_0045()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  livres text[] := array['eventos', 'status', 'atualizadoEm', 'confirmacao', 'cancelamento', 'reabertura'];
  a jsonb; b jsonb; k text; st0 text; st1 text; n int;
begin
  if new.colecao <> 'chamados' then return new; end if;
  if tg_op = 'INSERT' then
    if exists (select 1 from public.docs where colecao = new.colecao and id = new.id) then return new; end if; -- gravação de um que já existe: vale o UPDATE
    if coalesce(new.data ->> 'area', '') not in ('ti', 'predial') then raise exception 'chamado_area' using errcode = '22023'; end if;
    if new.data ->> 'numero' is null then
      perform pg_advisory_xact_lock(hashtext('chamados-' || (new.data ->> 'area')));
      select coalesce(max((data ->> 'numero')::int), 0) + 1 into n from public.docs where colecao = 'chamados' and data ->> 'area' = new.data ->> 'area' and (data ->> 'numero') ~ '^\d+$';
      new.data := jsonb_set(new.data, '{numero}', to_jsonb(n));
    end if;
    if auth.jwt() is not null then
      new.data := jsonb_set(new.data, '{solicitante}', coalesce(new.data -> 'solicitante', '{}'::jsonb)
        || jsonb_build_object('ref', coalesce(public.ref_atual(), ''), 'papel', coalesce(public.papel_atual(), '')));
      new.data := jsonb_set(new.data, '{status}', '"aberto"');
    end if;
    return new;
  end if;
  if auth.jwt() is null then return new; end if; -- manutenção direta no banco
  if public.chamado_atende_0045(old.data ->> 'area') then
    if (new.data -> 'solicitante') is distinct from (old.data -> 'solicitante') or (new.data -> 'numero') is distinct from (old.data -> 'numero') or (new.data ->> 'area') is distinct from (old.data ->> 'area') then
      raise exception 'chamado_travado' using errcode = '42501';
    end if;
    return new;
  end if;
  if coalesce(old.data -> 'solicitante' ->> 'ref', '') <> coalesce(public.ref_atual(), '') then raise exception 'chamado_sem_permissao' using errcode = '42501'; end if;
  a := old.data; b := new.data;
  foreach k in array livres loop a := a - k; b := b - k; end loop;
  if a is distinct from b then raise exception 'chamado_travado' using errcode = '42501'; end if;
  st0 := coalesce(old.data ->> 'status', ''); st1 := coalesce(new.data ->> 'status', '');
  if st0 <> st1 and not ((st0 = 'aberto' and st1 = 'cancelado') or (st0 = 'resolvido' and st1 in ('fechado', 'aberto'))) then
    raise exception 'chamado_travado' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function public.chamado_0045() from public, anon, authenticated;

create or replace trigger docs_chamado_0045 before insert or update on public.docs
  for each row execute function public.chamado_0045();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'chamados_0045') then
    create policy "chamados_0045" on public.docs as restrictive for all to authenticated
      using (colecao <> 'chamados' or public.chamado_visivel_0045(data))
      with check (colecao <> 'chamados' or public.chamado_visivel_0045(data));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'chamados_setor_0045') then
    create policy "chamados_setor_0045" on public.docs for all to authenticated
      using (colecao = 'chamados' and (select public.papel_atual()) = 'setor')
      with check (colecao = 'chamados' and (select public.papel_atual()) = 'setor');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'chamados_apaga_0045') then
    create policy "chamados_apaga_0045" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'chamados' or (select public.papel_atual()) = 'mestre');
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chamados', 'chamados', false, 8388608, array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'chamados: envia') then
    create policy "chamados: envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'chamados' and (select public.papel_atual()) in ('mestre', 'equipe', 'setor', 'motorista')
                  and name ~ '^(ti|predial)/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_.-]{1,120}$');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'chamados: le') then
    create policy "chamados: le" on storage.objects for select to authenticated
      using (bucket_id = 'chamados' and (select public.papel_atual()) in ('mestre', 'equipe', 'setor', 'motorista'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'chamados: mestre apaga') then
    create policy "chamados: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'chamados' and (select public.papel_atual()) = 'mestre' and not (select public.so_inclui()));
  end if;
end $$;
