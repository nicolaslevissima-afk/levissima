-- LEVÍSSIMA · 0038: revisão técnica do banco (29/10/2026).
--
-- * Chave das pesquisas (config/diretoria): a chave privada vai cifrada com a senha mestre. Até aqui qualquer login
--   (escritório, motorista) conseguia ler esse documento e tentar adivinhar a senha mestre fora do app, sem limite de
--   tentativas. Agora só o login da senha mestre lê o documento; os outros recebem só a parte pública (a que cifra as
--   respostas) pela função diretoria_publica().
-- * Login de motorista (senha individual): vê só o que é dele —
--   - cargas e registros de entrega em que ele é o motorista (pelo nome do login ou pelo nome atual do cadastro dele);
--   - o próprio cadastro em "motoristas" (o id do login motorista:<id>);
--   - nada da equipe (nomes, cargos, aniversários), das datas comemorativas e da agenda dos retornáveis.
--   O app do motorista já mostrava só isso; agora o banco também segura (senha de motorista vazada não abre o resto).
--   O resto que o app do motorista usa (produtos, estoque, rastreio, destinos do frete) continua igual.
-- (aplicada em partes: 0038a e 0038c em 29/10; 0038b — a regra da chave — logo depois de publicar o app novo; 0038d)

-- parte pública da chave das pesquisas (para cifrar as respostas de motoristas e clientes)
create or replace function public.diretoria_publica()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when public.papel_atual() in ('mestre', 'equipe', 'motorista') then
    (select jsonb_build_object('pub', d.data ->> 'pub', 'chaveId', d.data ->> 'chaveId')
       from public.docs d where d.colecao = 'config' and d.id = 'diretoria' and coalesce(d.data ->> 'pub', '') <> '')
  end;
$$;
revoke execute on function public.diretoria_publica() from public, anon;
grant execute on function public.diretoria_publica() to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'diretoria_chave_0038') then
    create policy "diretoria_chave_0038" on public.docs as restrictive for all to authenticated
      using (colecao <> 'config' or id <> 'diretoria' or ((select public.papel_atual()) = 'mestre' and (select public.ref_atual()) = 'mestre'))
      with check (colecao <> 'config' or id <> 'diretoria' or ((select public.papel_atual()) = 'mestre' and (select public.ref_atual()) = 'mestre'));
  end if;
end $$;

-- nome atual do motorista logado (do cadastro dele), em minúsculas e sem espaços nas pontas
create or replace function public.motorista_nome_0038()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select lower(btrim(coalesce((select d.data ->> 'nome' from public.docs d
                                where d.colecao = 'motoristas' and d.id = split_part(public.ref_atual(), ':', 2)
                                  and public.ref_atual() like 'motorista:%'), '')));
$$;
revoke execute on function public.motorista_nome_0038() from public, anon;
grant execute on function public.motorista_nome_0038() to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'motorista_so_o_dele_0038') then
    create policy "motorista_so_o_dele_0038" on public.docs as restrictive for all to authenticated
      using ((select public.papel_atual()) <> 'motorista' or case
        when colecao in ('equipe', 'datas-comemorativas', 'agenda-fixos', 'z-teste-implantacao') then false
        when colecao = 'motoristas' then id = split_part((select public.ref_atual()), ':', 2)
        when colecao in ('cargas', 'registros') then lower(btrim(coalesce(data ->> 'motorista', ''))) <> ''
          and lower(btrim(data ->> 'motorista')) in (lower(btrim(coalesce((select auth.jwt() -> 'app_metadata' ->> 'nome'), ''))), (select public.motorista_nome_0038()))
        else true end)
      with check ((select public.papel_atual()) <> 'motorista' or case
        when colecao in ('equipe', 'datas-comemorativas', 'agenda-fixos', 'z-teste-implantacao') then false
        when colecao = 'motoristas' then id = split_part((select public.ref_atual()), ':', 2)
        when colecao in ('cargas', 'registros') then lower(btrim(coalesce(data ->> 'motorista', ''))) <> ''
          and lower(btrim(data ->> 'motorista')) in (lower(btrim(coalesce((select auth.jwt() -> 'app_metadata' ->> 'nome'), ''))), (select public.motorista_nome_0038()))
        else true end);
  end if;
end $$;

-- * Login sem papel (conta criada fora do app, se o cadastro aberto do Supabase Auth estiver ligado): não vê nada.
--   Faltavam dois pontos: os recados do mural e o aniversariante do dia. (0038d)
create or replace function public.aniversariantes_hoje()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with h as (select (now() at time zone 'America/Sao_Paulo')::date as d)
  select coalesce(jsonb_agg(jsonb_build_object('nome', e.data ->> 'nome', 'setor', coalesce(e.data ->> 'area', '')) order by e.data ->> 'nome'), '[]'::jsonb)
    from public.docs e, h
   where public.papel_atual() <> ''
     and e.colecao = 'equipe' and coalesce(e.data ->> 'aniversario', '') <> '' and e.data ->> 'ativo' is distinct from 'false'
     and (e.data ->> 'aniversario' = to_char(h.d, 'MM-DD')
          or (e.data ->> 'aniversario' = '02-29' and to_char(h.d, 'MM-DD') = '02-28'
              and extract(day from (date_trunc('year', h.d) + interval '2 month' - interval '1 day')) = 28));
$$;

alter policy "mural_le_0008" on public.docs using (colecao = 'mural' and (select public.papel_atual()) <> '');
