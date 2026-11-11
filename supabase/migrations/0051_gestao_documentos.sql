-- LEVÍSSIMA · 0051: Qualidade › Documentos, fase 1 da gestão documental do SGSA (pedido de 11/11/2026).
--
-- * Fluxo: quem tem a aba Qualidade elabora; quem está marcado "Revisa e aprova documentos da qualidade"
--   (gestorDocumentos em Cadastros › Equipe) ou a senha mestre revisa e aprova, nunca a versão que elaborou. O gatilho
--   qd_documento_guarda_0051 confere em qualidade-documentos:
--     * o histórico de versões não encolhe e as versões antigas não mudam;
--     * a revisão (rascunho.revisado) é de quem aprova documentos e não está entre os elaboradores da versão;
--     * a versão interna só fica vigente aprovada por quem aprova documentos e não a elaborou.
--   Chave de quem assina: eq-<id da pessoa da equipe> ou r-<referência do acesso>.
-- * Classificação: "confidencial" só quem aprova documentos e a senha mestre leem (documento e arquivos); versões
--   antigas e o arquivo editável (Word/Excel) da vigente com PDF, só quem aprova documentos baixa.
-- * Coleções novas: qualidade-doc-config (lista de requisitos normativos; grava quem aprova documentos) e
--   qualidade-doc-treinamentos (lista de presença da reciclagem no RH; ninguém altera, só a senha mestre apaga).
-- * Tablets de setor: qd_docs_setor_0051 entrega só os vigentes de uso geral marcados para o setor; o arquivo de
--   leitura (PDF ou foto) desses documentos abre pelo balde; qd_ler_setor_0051 grava o "Li e entendi" conferindo a
--   senha de 4 números no servidor (pin_conferir, com o mesmo limite de tentativas).
-- * RH: qd_rh_funcoes_0051 e qd_rh_funcionarios_0051 (nome, função e setor dos funcionários ativos, para a lista de
--   presença) para quem tem a aba Qualidade; qd_rh_reciclagens_0051 (POPs da função e o último treinamento) para quem
--   tem o RH ou a Qualidade. qd_setores_0051: nome dos acessos de setor (tablets) para quem tem a aba Qualidade.

-- ---------- quem aprova documentos ----------
create or replace function public.qd_gestor_0051()
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
  return coalesce(m -> 'gestorDocumentos' = 'true'::jsonb, false);
end $$;
revoke execute on function public.qd_gestor_0051() from public, anon;
grant execute on function public.qd_gestor_0051() to authenticated;

create or replace function public.qd_chave_0051(p jsonb)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when p is null or jsonb_typeof(p) is distinct from 'object' then ''
              when coalesce(p ->> 'id', '') <> '' then 'eq-' || (p ->> 'id')
              else 'r-' || coalesce(p ->> 'ref', p ->> 'nome', '') end;
$$;
revoke execute on function public.qd_chave_0051(jsonb) from public, anon;
grant execute on function public.qd_chave_0051(jsonb) to authenticated;

create or replace function public.qd_elaboradores_0051(v jsonb)
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $$
  select array(select x from jsonb_array_elements_text(case when jsonb_typeof(v -> 'elaboradores') = 'array' then v -> 'elaboradores' else '[]'::jsonb end) x
               union select public.qd_chave_0051(v -> 'elaborado'));
$$;
revoke execute on function public.qd_elaboradores_0051(jsonb) from public, anon, authenticated;

-- a assinatura é de quem aprova documentos (pessoa marcada ou a senha mestre/diretoria)?
create or replace function public.qd_assinante_ok_0051(p jsonb)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when coalesce(p ->> 'id', '') <> ''
              then exists (select 1 from public.docs e where e.colecao = 'equipe' and e.id = p ->> 'id' and e.data -> 'gestorDocumentos' = 'true'::jsonb)
              else coalesce(p ->> 'ref', '') = 'mestre' or coalesce(p ->> 'ref', '') like 'diretoria:%' end;
$$;
revoke execute on function public.qd_assinante_ok_0051(jsonb) from public, anon, authenticated;

-- ---------- gatilho do documento ----------
create or replace function public.qd_documento_guarda_0051()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ho jsonb; hn jsonb; i int; interno boolean;
  nv jsonb := new.data -> 'vigente'; nr jsonb := new.data -> 'rascunho';
  ov jsonb; orr jsonb;
begin
  if new.colecao <> 'qualidade-documentos' then return new; end if;
  interno := coalesce(new.data ->> 'tipo', '') in ('pop', 'manual', 'procedimento', 'politica', 'registro', 'formulario', 'appcc', 'especificacao');
  if tg_op = 'UPDATE' then
    ho := case when jsonb_typeof(old.data -> 'historico') = 'array' then old.data -> 'historico' else '[]'::jsonb end;
    hn := case when jsonb_typeof(new.data -> 'historico') = 'array' then new.data -> 'historico' else '[]'::jsonb end;
    if jsonb_array_length(hn) < jsonb_array_length(ho) then
      raise exception 'documentos: o histórico de versões não pode ser apagado' using errcode = '42501';
    end if;
    for i in 0 .. jsonb_array_length(ho) - 1 loop
      if (hn -> i) is distinct from (ho -> i) then
        raise exception 'documentos: versão antiga não pode ser alterada' using errcode = '42501';
      end if;
    end loop;
    ov := old.data -> 'vigente'; orr := old.data -> 'rascunho';
  end if;
  -- revisão nova: de quem aprova documentos e não elaborou a versão
  if jsonb_typeof(nr) = 'object' and jsonb_typeof(nr -> 'revisado') = 'object'
     and (jsonb_typeof(orr) is distinct from 'object' or (orr -> 'revisado') is distinct from (nr -> 'revisado')) then
    if public.qd_chave_0051(nr -> 'revisado') = any (public.qd_elaboradores_0051(nr)) then
      raise exception 'documentos: quem elaborou não revisa a mesma versão' using errcode = '42501';
    end if;
    if not public.qd_assinante_ok_0051(nr -> 'revisado') then
      raise exception 'documentos: a revisão é de quem revisa e aprova documentos' using errcode = '42501';
    end if;
  end if;
  -- versão interna nova vigente: aprovada por quem aprova documentos e não a elaborou
  if interno and jsonb_typeof(nv) = 'object'
     and (jsonb_typeof(ov) is distinct from 'object' or (ov -> 'versao') is distinct from (nv -> 'versao')) then
    if jsonb_typeof(nv -> 'aprovado') is distinct from 'object' then
      raise exception 'documentos: versão sem aprovação não fica vigente' using errcode = '42501';
    end if;
    if public.qd_chave_0051(nv -> 'aprovado') = any (public.qd_elaboradores_0051(nv)) then
      raise exception 'documentos: quem elaborou não aprova a mesma versão' using errcode = '42501';
    end if;
    if not public.qd_assinante_ok_0051(nv -> 'aprovado') then
      raise exception 'documentos: a aprovação é de quem revisa e aprova documentos' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.qd_documento_guarda_0051() from public, anon, authenticated;

drop trigger if exists qd_documento_guarda_0051 on public.docs;
create trigger qd_documento_guarda_0051 before insert or update on public.docs
  for each row when (new.colecao = 'qualidade-documentos') execute function public.qd_documento_guarda_0051();

-- ---------- regras das coleções ----------
create or replace function public.colecao_documentos_0051(p_colecao text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$ select p_colecao in ('qualidade-doc-config', 'qualidade-doc-treinamentos'); $$;
revoke execute on function public.colecao_documentos_0051(text) from public, anon;
grant execute on function public.colecao_documentos_0051(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_confidencial_0051') then
    create policy "qualidade_confidencial_0051" on public.docs as restrictive for select to authenticated
      using (colecao <> 'qualidade-documentos' or coalesce(data ->> 'classificacao', '') <> 'confidencial' or (select public.qd_gestor_0051()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_docs_novas_le_0051') then
    create policy "qualidade_docs_novas_le_0051" on public.docs as restrictive for select to authenticated
      using (not public.colecao_documentos_0051(colecao) or (select public.ve_aba_0033('qualidade')));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_docs_novas_grava_0051') then
    create policy "qualidade_docs_novas_grava_0051" on public.docs as restrictive for insert to authenticated
      with check (not public.colecao_documentos_0051(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver())
                  and (colecao <> 'qualidade-doc-config' or (select public.qd_gestor_0051()))));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_docs_novas_altera_0051') then
    create policy "qualidade_docs_novas_altera_0051" on public.docs as restrictive for update to authenticated
      using (not public.colecao_documentos_0051(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver())
             and ((colecao = 'qualidade-doc-config' and (select public.qd_gestor_0051())) or (select public.papel_atual()) = 'mestre')))
      with check (not public.colecao_documentos_0051(colecao) or ((select public.ve_aba_0033('qualidade')) and not (select public.so_ver())
             and ((colecao = 'qualidade-doc-config' and (select public.qd_gestor_0051())) or (select public.papel_atual()) = 'mestre')));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'qualidade_docs_novas_apaga_0051') then
    create policy "qualidade_docs_novas_apaga_0051" on public.docs as restrictive for delete to authenticated
      using (not public.colecao_documentos_0051(colecao) or ((select public.papel_atual()) = 'mestre' and not (select public.so_inclui())));
  end if;
end $$;

-- ---------- arquivos ----------
-- arquivo de leitura da versão: o PDF, ou o próprio arquivo quando é PDF ou foto
create or replace function public.qd_arquivo_leitura_0051(v jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when jsonb_typeof(v -> 'pdf') = 'object' then v -> 'pdf'
              when jsonb_typeof(v -> 'arquivo') = 'object' and (coalesce(v -> 'arquivo' ->> 'tipo', '') ~* '(^image/|pdf)' or coalesce(v -> 'arquivo' ->> 'nome', '') ~* '\.pdf$') then v -> 'arquivo'
              else null end;
$$;
revoke execute on function public.qd_arquivo_leitura_0051(jsonb) from public, anon;
grant execute on function public.qd_arquivo_leitura_0051(jsonb) to authenticated;

-- quem pode baixar o arquivo (além das regras da 0033): confidencial e versões antigas só quem aprova documentos
create or replace function public.qd_arquivo_pode_0051(p_nome text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare d jsonb;
begin
  select data into d from public.docs where colecao = 'qualidade-documentos' and id = split_part(p_nome, '/', 2);
  if d is null then return true; end if;
  if coalesce(d ->> 'classificacao', '') = 'confidencial' then return public.qd_gestor_0051(); end if;
  if p_nome in (coalesce(d -> 'rascunho' -> 'arquivo' ->> 'caminho', ''), coalesce(d -> 'rascunho' -> 'pdf' ->> 'caminho', ''), coalesce(d -> 'vigente' -> 'pdf' ->> 'caminho', '')) then
    return true;
  end if;
  if p_nome = coalesce(d -> 'vigente' -> 'arquivo' ->> 'caminho', '') then
    return jsonb_typeof(d -> 'vigente' -> 'pdf') is distinct from 'object' or public.qd_gestor_0051();
  end if;
  if exists (select 1 from jsonb_array_elements(case when jsonb_typeof(d -> 'historico') = 'array' then d -> 'historico' else '[]'::jsonb end) h
             where h -> 'arquivo' ->> 'caminho' = p_nome or h -> 'pdf' ->> 'caminho' = p_nome) then
    return public.qd_gestor_0051();
  end if;
  return true;
end $$;
revoke execute on function public.qd_arquivo_pode_0051(text) from public, anon;
grant execute on function public.qd_arquivo_pode_0051(text) to authenticated;

-- tablet de setor: só o arquivo de leitura da versão vigente de uso geral marcada para o setor
create or replace function public.qd_arquivo_setor_0051(p_nome text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.docs d
                  where d.colecao = 'qualidade-documentos' and d.id = split_part(p_nome, '/', 2)
                    and jsonb_typeof(d.data -> 'vigente') = 'object' and coalesce(jsonb_typeof(d.data -> 'obsoleto'), 'null') = 'null'
                    and coalesce(d.data ->> 'classificacao', 'geral') = 'geral'
                    and coalesce(d.data -> 'locais', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('ref', public.ref_atual()))
                    and public.qd_arquivo_leitura_0051(d.data -> 'vigente') ->> 'caminho' = p_nome);
$$;
revoke execute on function public.qd_arquivo_setor_0051(text) from public, anon;
grant execute on function public.qd_arquivo_setor_0051(text) to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'qualidade-docs: restrito 0051') then
    create policy "qualidade-docs: restrito 0051" on storage.objects as restrictive for select to authenticated
      using (bucket_id <> 'qualidade-docs' or public.qd_arquivo_pode_0051(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'qualidade-docs: setor le 0051') then
    create policy "qualidade-docs: setor le 0051" on storage.objects for select to authenticated
      using (bucket_id = 'qualidade-docs' and (select public.papel_atual()) = 'setor' and public.qd_arquivo_setor_0051(name));
  end if;
end $$;

-- ---------- tablets de setor ----------
create or replace function public.qd_setores_0051()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.ve_aba_0033('qualidade') then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ref', s.ref, 'nome', s.nome) order by s.nome)
                     from public.acesso_senhas s where s.papel = 'setor' and s.nome !~* 'desativad'), '[]'::jsonb);
end $$;
revoke execute on function public.qd_setores_0051() from public, anon;
grant execute on function public.qd_setores_0051() to authenticated;

create or replace function public.qd_docs_setor_0051()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), '');
begin
  if coalesce(public.papel_atual(), '') <> 'setor' or r = '' then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
             'id', d.id, 'codigo', d.data ->> 'codigo', 'titulo', d.data ->> 'titulo', 'tipo', d.data ->> 'tipo',
             'leituraObrigatoria', coalesce(d.data -> 'leituraObrigatoria', 'false'::jsonb),
             'vigente', jsonb_build_object('versao', d.data -> 'vigente' -> 'versao', 'conteudo', d.data -> 'vigente' -> 'conteudo',
                                           'aprovado', d.data -> 'vigente' -> 'aprovado', 'emissao', d.data -> 'vigente' -> 'emissao',
                                           'validade', d.data -> 'vigente' -> 'validade', 'pdf', public.qd_arquivo_leitura_0051(d.data -> 'vigente')),
             'lidos', (select count(*) from public.docs l where l.colecao = 'qualidade-doc-leituras' and l.data ->> 'docId' = d.id
                         and l.data -> 'versao' = d.data -> 'vigente' -> 'versao'))
           order by d.data ->> 'codigo')
           from public.docs d
          where d.colecao = 'qualidade-documentos' and jsonb_typeof(d.data -> 'vigente') = 'object'
            and coalesce(jsonb_typeof(d.data -> 'obsoleto'), 'null') = 'null' and coalesce(d.data ->> 'classificacao', 'geral') = 'geral'
            and coalesce(d.data -> 'locais', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('ref', r))), '[]'::jsonb);
end $$;
revoke execute on function public.qd_docs_setor_0051() from public, anon;
grant execute on function public.qd_docs_setor_0051() to authenticated;

-- "Li e entendi" no tablet: confere a senha de 4 números no servidor e grava a leitura da versão vigente
create or replace function public.qd_ler_setor_0051(p_doc text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r text := coalesce(public.ref_atual(), ''); d jsonb; c jsonb; m jsonb; chave text; nome text;
begin
  if coalesce(public.papel_atual(), '') <> 'setor' or r = '' then raise exception 'permissao' using errcode = '42501'; end if;
  select data into d from public.docs where colecao = 'qualidade-documentos' and id = p_doc;
  if d is null or jsonb_typeof(d -> 'vigente') is distinct from 'object' or coalesce(jsonb_typeof(d -> 'obsoleto'), 'null') <> 'null'
     or coalesce(d ->> 'classificacao', 'geral') <> 'geral'
     or not (coalesce(d -> 'locais', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('ref', r))) then
    raise exception 'documento' using errcode = '22023';
  end if;
  c := public.pin_conferir(p_pin);
  if not coalesce((c ->> 'ok')::boolean, false) then return c; end if;
  select data into m from public.docs where colecao = 'equipe' and id = c ->> 'membro';
  nome := coalesce(nullif(m ->> 'nomeCompleto', ''), m ->> 'nome', '');
  chave := p_doc || '_v' || (d -> 'vigente' ->> 'versao') || '_eq-' || (c ->> 'membro');
  if exists (select 1 from public.docs where colecao = 'qualidade-doc-leituras' and id = chave) then
    return jsonb_build_object('ok', true, 'ja', true, 'nome', nome);
  end if;
  insert into public.docs (colecao, id, data) values ('qualidade-doc-leituras', chave, jsonb_build_object(
    'docId', p_doc, 'codigo', d ->> 'codigo', 'versao', d -> 'vigente' -> 'versao', 'nome', nome, 'pessoaId', c ->> 'membro',
    'ref', r, 'origem', 'tablet', 'em', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  return jsonb_build_object('ok', true, 'nome', nome);
end $$;
revoke execute on function public.qd_ler_setor_0051(text, text) from public, anon;
grant execute on function public.qd_ler_setor_0051(text, text) to authenticated;

-- ---------- RH: funções, funcionários e reciclagens ----------
create or replace function public.qd_rh_funcoes_0051()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.ve_aba_0033('qualidade') then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(f order by f) from (
            select distinct btrim(dados ->> 'funcao') f from public.modulo_docs
             where modulo = 'uniformes' and caminho = 'funcionarios' and coalesce(dados -> 'ativo', 'true'::jsonb) <> 'false'::jsonb
               and btrim(coalesce(dados ->> 'funcao', '')) <> '') x), '[]'::jsonb);
end $$;
revoke execute on function public.qd_rh_funcoes_0051() from public, anon;
grant execute on function public.qd_rh_funcoes_0051() to authenticated;

create or replace function public.qd_rh_funcionarios_0051(p_funcoes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.ve_aba_0033('qualidade') then raise exception 'permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', dados ->> 'nome', 'funcao', btrim(coalesce(dados ->> 'funcao', '')), 'setor', coalesce(dados ->> 'setor', '')) order by dados ->> 'nome')
                     from public.modulo_docs
                    where modulo = 'uniformes' and caminho = 'funcionarios' and coalesce(dados -> 'ativo', 'true'::jsonb) <> 'false'::jsonb
                      and lower(btrim(coalesce(dados ->> 'funcao', ''))) in (select lower(btrim(x)) from unnest(coalesce(p_funcoes, '{}'::text[])) x)), '[]'::jsonb);
end $$;
revoke execute on function public.qd_rh_funcionarios_0051(text[]) from public, anon;
grant execute on function public.qd_rh_funcionarios_0051(text[]) to authenticated;

create or replace function public.qd_rh_reciclagens_0051(p_funcionario text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare f jsonb; fn text;
begin
  if not (public.ve_aba_marcada_0042('rh') or public.ve_aba_0033('qualidade')) then raise exception 'permissao' using errcode = '42501'; end if;
  select dados into f from public.modulo_docs where modulo = 'uniformes' and caminho = 'funcionarios' and id = p_funcionario;
  fn := lower(btrim(coalesce(f ->> 'funcao', '')));
  if f is null or fn = '' then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
             'docId', d.id, 'codigo', d.data ->> 'codigo', 'titulo', d.data ->> 'titulo', 'versao', d.data -> 'vigente' -> 'versao',
             'desde', d.data -> 'vigente' -> 'aprovado' ->> 'em',
             'treinamento', (select jsonb_build_object('versao', t.data -> 'versao', 'data', t.data ->> 'data') from public.docs t
                              where t.colecao = 'qualidade-doc-treinamentos' and t.data ->> 'docId' = d.id and t.data ->> 'funcionarioId' = p_funcionario
                              order by t.data -> 'versao' desc, t.data ->> 'data' desc limit 1))
           order by d.data ->> 'codigo')
           from public.docs d
          where d.colecao = 'qualidade-documentos' and jsonb_typeof(d.data -> 'vigente') = 'object'
            and coalesce(jsonb_typeof(d.data -> 'obsoleto'), 'null') = 'null'
            and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(d.data -> 'funcoesRH') = 'array' then d.data -> 'funcoesRH' else '[]'::jsonb end) x
                         where lower(btrim(x)) = fn)), '[]'::jsonb);
end $$;
revoke execute on function public.qd_rh_reciclagens_0051(text) from public, anon;
grant execute on function public.qd_rh_reciclagens_0051(text) to authenticated;
