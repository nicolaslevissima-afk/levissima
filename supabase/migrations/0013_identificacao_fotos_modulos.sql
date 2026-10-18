-- LEVÍSSIMA · 0013: identificação automática nos módulos e fotos dos chamados da Manutenção (pedido de 17/10/2026).
--
-- 1. minha_identificacao(): quem está usando o app, pelo próprio acesso (nome da senha). Devolve só os dados de
--    quem chamou: nome, papel, função, turno e setor. A função é o cargo do organograma (Cadastros › Equipe, ex.:
--    "Coordenador · Manutenção") ou, sem cargo, a função do cadastro de funcionários (RH, módulo Uniformes e EPI) com o
--    mesmo nome (ou o único cujo nome começa pelo nome do acesso); o turno vem do RH. Assim o chamado da Manutenção sai com nome, função e turno sem
--    ninguém digitar.
-- 2. Bucket PRIVADO "modulos-fotos" (até 5 MB, só imagens): fotos tiradas nos módulos, em <módulo>/... Lê e envia
--    quem tem acesso ao módulo (pode_modulo); só a senha mestre apaga.

create or replace function public.minha_identificacao()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_papel text := public.papel_atual();
  v_nome text := btrim(coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', ''));
  k text := public.sem_acento_0009(btrim(coalesce(auth.jwt() -> 'app_metadata' ->> 'nome', '')));
  eq jsonb;
  rh jsonb;
  n int;
  v_cargo text;
  v_turno text;
begin
  if v_papel = '' then
    return null;
  end if;
  if k = '' then
    return jsonb_build_object('nome', v_nome, 'papel', v_papel, 'funcao', '', 'turno', '', 'setor', '', 'cargo', '');
  end if;
  -- organograma (Cadastros › Equipe)
  select d.data into eq from public.docs d
   where d.colecao = 'equipe' and public.sem_acento_0009(d.data ->> 'nome') = k
   order by (d.data ? 'cargo') desc limit 1;
  -- RH: o mesmo nome; senão, o único funcionário ativo cujo nome começa pelo nome do acesso
  select count(*) into n from public.modulo_docs m
   where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
     and public.sem_acento_0009(m.dados ->> 'nome') = k;
  if n = 1 then
    select m.dados into rh from public.modulo_docs m
     where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
       and public.sem_acento_0009(m.dados ->> 'nome') = k;
  elsif n = 0 then
    select count(*) into n from public.modulo_docs m
     where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
       and public.sem_acento_0009(m.dados ->> 'nome') like k || ' %';
    if n = 1 then
      select m.dados into rh from public.modulo_docs m
       where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
         and public.sem_acento_0009(m.dados ->> 'nome') like k || ' %';
    end if;
  end if;
  v_cargo := case eq ->> 'cargo' when 'diretor' then 'Diretor' when 'gerente' then 'Gerente' when 'coordenador' then 'Coordenador'
    when 'supervisor' then 'Supervisor' when 'analista' then 'Analista' when 'assistente' then 'Assistente' when 'lider' then 'Líder'
    when 'operador' then 'Operador' else '' end;
  v_turno := case coalesce(rh -> 'rh' ->> 'turno', '') when 'desc1' then 'Desc 1 (6x1)' when 'desc2' then 'Desc 2 (6x1)' when 'desc3' then 'Desc 3 (5x2)'
    when 'galao-dia' then 'Galão · turno dia' when 'galao-noite' then 'Galão · turno noite' when 'adm' then 'Administrativo'
    when 'especial' then 'Horário especial' else '' end;
  return jsonb_build_object(
    'nome', v_nome,
    'papel', v_papel,
    'funcao', coalesce(nullif(btrim(v_cargo || coalesce(' · ' || nullif(eq ->> 'area', ''), '')), ''), nullif(btrim(rh ->> 'funcao'), ''), ''),
    'funcaoRh', coalesce(nullif(btrim(rh ->> 'funcao'), ''), ''),
    'turno', v_turno,
    'setor', coalesce(nullif(eq ->> 'area', ''), nullif(btrim(rh ->> 'setor'), ''), ''),
    'cargo', v_cargo);
end;
$$;
revoke execute on function public.minha_identificacao() from public, anon;
grant execute on function public.minha_identificacao() to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('modulos-fotos', 'modulos-fotos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-fotos: quem usa o modulo le') then
    create policy "modulos-fotos: quem usa o modulo le" on storage.objects for select to authenticated
      using (bucket_id = 'modulos-fotos' and public.pode_modulo(split_part(name, '/', 1)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-fotos: quem usa o modulo envia') then
    create policy "modulos-fotos: quem usa o modulo envia" on storage.objects for insert to authenticated
      with check (bucket_id = 'modulos-fotos' and public.pode_modulo(split_part(name, '/', 1)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'modulos-fotos: mestre apaga') then
    create policy "modulos-fotos: mestre apaga" on storage.objects for delete to authenticated
      using (bucket_id = 'modulos-fotos' and (select public.papel_atual()) = 'mestre');
  end if;
end $$;
