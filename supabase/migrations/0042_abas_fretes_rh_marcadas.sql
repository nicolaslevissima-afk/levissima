-- 0042 · Abas Fretes e RH liberadas pela senha mestre para quem ela marcar (03/11/2026)
--
-- Antes, Fretes e RH eram só da senha mestre. Agora, em Cadastros › Equipe com senha, a senha mestre marca no
-- acesso individual de uma pessoa as caixas "Fretes" e/ou "RH" (nível Edita ou Só visualiza). No token vão
-- 'abas' + 'aba:fretes' / 'aba:rh' (e 'ver:<aba>' quando só visualiza), validados pela função "acesso".
-- A senha da equipe (sem a marca 'abas') nunca vê estas abas: aqui a aba precisa estar marcada de verdade
-- (diferente de ve_aba_0033, que libera tudo quando a lista de abas não foi escolhida).
--
-- Fretes: 'fretes' e 'fretes-tabela' (lê; grava quem tem a aba em Edita) e 'transportadoras' (lê; grava só a
-- senha mestre, o cadastro fica em Cadastros). Os dados pessoais e os documentos dos motoristas ('motorista-docs'
-- e o bucket privado) e os representantes continuam só da senha mestre (colecao_so_mestre).
-- RH: o cadastro de funcionários e treinamentos do módulo Uniformes e EPI (modulo_docs, módulo 'uniformes').

create or replace function public.ve_aba_marcada_0042(p_aba text)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() = 'equipe'
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?& array['abas', 'aba:' || p_aba], false));
$$;

-- grava: aba marcada em Edita (sem 'ver:' nem 'inclui:') e o token sem so_ver/so_inclui
create or replace function public.grava_aba_marcada_0042(p_aba text)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select public.papel_atual() = 'mestre'
      or (public.papel_atual() = 'equipe'
          and coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?& array['abas', 'aba:' || p_aba], false)
          and not coalesce((auth.jwt() -> 'app_metadata' -> 'modulos') ?| array['ver:' || p_aba, 'inclui:' || p_aba], false)
          and not public.so_ver() and not public.so_inclui());
$$;

create or replace function public.colecao_fretes_0042(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_colecao in ('fretes', 'fretes-tabela', 'transportadoras');
$$;

-- 0042a · docs: as regras novas entram antes de tirar as três coleções da regra "só a senha mestre"
create policy fretes_le_0042 on public.docs as restrictive for select to authenticated
  using ((not public.colecao_fretes_0042(colecao)) or (select public.ve_aba_marcada_0042('fretes')));

create policy fretes_grava_0042 on public.docs as restrictive for insert to authenticated
  with check ((not public.colecao_fretes_0042(colecao))
              or (select public.papel_atual()) = 'mestre'
              or (colecao <> 'transportadoras' and (select public.grava_aba_marcada_0042('fretes'))));

create policy fretes_altera_0042 on public.docs as restrictive for update to authenticated
  using ((not public.colecao_fretes_0042(colecao))
         or (select public.papel_atual()) = 'mestre'
         or (colecao <> 'transportadoras' and (select public.grava_aba_marcada_0042('fretes'))))
  with check ((not public.colecao_fretes_0042(colecao))
              or (select public.papel_atual()) = 'mestre'
              or (colecao <> 'transportadoras' and (select public.grava_aba_marcada_0042('fretes'))));

create policy fretes_apaga_0042 on public.docs as restrictive for delete to authenticated
  using ((not public.colecao_fretes_0042(colecao)) or (select public.papel_atual()) = 'mestre');

-- 0042b · a regra "só a senha mestre" fica com os dados pessoais (motoristas e representantes)
create or replace function public.colecao_so_mestre(p_colecao text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_colecao in ('motorista-docs', 'representantes', 'representante-docs');
$$;

-- 0042c · RH: o cadastro de funcionários do módulo Uniformes e EPI para quem tem a aba RH marcada
create policy rh_le_0042 on public.modulo_docs for select to authenticated
  using (modulo = 'uniformes' and caminho in ('funcionarios', 'treinamentos', 'nrTipos', 'config')
         and (select public.ve_aba_marcada_0042('rh')));

create policy rh_grava_0042 on public.modulo_docs for insert to authenticated
  with check (modulo = 'uniformes' and caminho in ('funcionarios', 'treinamentos')
              and (select public.grava_aba_marcada_0042('rh')));

create policy rh_altera_0042 on public.modulo_docs for update to authenticated
  using (modulo = 'uniformes' and caminho in ('funcionarios', 'treinamentos') and (select public.grava_aba_marcada_0042('rh')))
  with check (modulo = 'uniformes' and caminho in ('funcionarios', 'treinamentos') and (select public.grava_aba_marcada_0042('rh')));
