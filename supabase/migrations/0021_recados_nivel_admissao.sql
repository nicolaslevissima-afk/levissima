-- LEVÍSSIMA · 0021: recados com público escolhido, nível "só visualiza" no banco e data de admissão na identificação
-- (pedidos de 19/10/2026).
--
-- * Recados em destaque (coleção "mural"): agora são vários, e cada um vale para todos (campo "para" vazio) ou só
--   para os acessos escolhidos (lista de refs em "para"). Quem não está na lista nem lê o recado; a senha mestre
--   (e a diretoria, que entra como mestre) lê todos para poder cuidar deles em Cadastros.
-- * Nível de acesso por aba (Cadastros › Equipe com senha): com "só visualiza" em todas as abas marcadas, a função de
--   acesso põe so_ver no login e o banco recusa qualquer gravação na tabela docs; com "só inclui" (ou só visualiza e
--   só inclui) em todas, põe so_inclui (regras da 0014: não altera nem apaga). Níveis diferentes por aba: quem segura é
--   o app, pela aba aberta.
-- * minha_identificacao devolve também a data de admissão do RH ("admissao"), para a mensagem de tempo de casa.

-- ---------- recados ----------
create or replace function public.recado_visivel_0021(p_data jsonb)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.papel_atual() = 'mestre'
      or jsonb_typeof(p_data -> 'para') is distinct from 'array'
      or jsonb_array_length(p_data -> 'para') = 0
      or (public.ref_atual() <> '' and (p_data -> 'para') ? public.ref_atual());
$$;
revoke execute on function public.recado_visivel_0021(jsonb) from public, anon;
grant execute on function public.recado_visivel_0021(jsonb) to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'mural_para_0021') then
    create policy mural_para_0021 on public.docs as restrictive for select to authenticated
      using (colecao <> 'mural' or public.recado_visivel_0021(data));
  end if;
end $$;

-- ---------- só visualiza ----------
create or replace function public.so_ver()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'so_ver')::boolean, false); $$;
revoke execute on function public.so_ver() from public, anon;
grant execute on function public.so_ver() to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_ver_nao_grava_0021') then
    create policy so_ver_nao_grava_0021 on public.docs as restrictive for insert to authenticated with check (not (select public.so_ver()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_ver_nao_altera_0021') then
    create policy so_ver_nao_altera_0021 on public.docs as restrictive for update to authenticated using (not (select public.so_ver())) with check (not (select public.so_ver()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'so_ver_nao_apaga_0021') then
    create policy so_ver_nao_apaga_0021 on public.docs as restrictive for delete to authenticated using (not (select public.so_ver()));
  end if;
end $$;

-- ---------- identificação com a data de admissão (mesma função da 0018 + "admissao") ----------
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
  kc text;
  v_completo text;
  v_curto text;
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
    return jsonb_build_object('nome', v_nome, 'nomeCompleto', v_nome, 'papel', v_papel, 'funcao', '', 'funcaoRh', '', 'turno', '', 'setor', '', 'cargo', '');
  end if;
  -- organograma (Cadastros › Equipe com senha): o mesmo nome...
  select d.data into eq from public.docs d
   where d.colecao = 'equipe' and public.sem_acento_0009(d.data ->> 'nome') = k
   order by (d.data ? 'cargo') desc limit 1;
  -- ... senão o único cadastro cujo nome completo começa pelo nome do acesso ("Ana" → "Ana Maria da Silva")
  if eq is null then
    select count(*) into n from public.docs d
     where d.colecao = 'equipe' and left(public.sem_acento_0009(d.data ->> 'nome'), length(k) + 1) = k || ' ';
    if n = 1 then
      select d.data into eq from public.docs d
       where d.colecao = 'equipe' and left(public.sem_acento_0009(d.data ->> 'nome'), length(k) + 1) = k || ' ';
    end if;
  end if;
  -- ... senão o único cadastro cujo nome é o começo do nome do acesso ("Ana Maria da Silva" → "Ana")
  if eq is null then
    select count(*) into n from public.docs d
     where d.colecao = 'equipe' and public.sem_acento_0009(d.data ->> 'nome') <> ''
       and left(k, length(public.sem_acento_0009(d.data ->> 'nome')) + 1) = public.sem_acento_0009(d.data ->> 'nome') || ' ';
    if n = 1 then
      select d.data into eq from public.docs d
       where d.colecao = 'equipe' and public.sem_acento_0009(d.data ->> 'nome') <> ''
         and left(k, length(public.sem_acento_0009(d.data ->> 'nome')) + 1) = public.sem_acento_0009(d.data ->> 'nome') || ' ';
    end if;
  end if;
  -- o nome mais completo que se tem: o do organograma (com acentos), se não for menor que o do acesso
  v_completo := v_nome;
  if eq is not null and length(btrim(coalesce(eq ->> 'nome', ''))) >= length(v_nome) then
    v_completo := btrim(eq ->> 'nome');
  end if;
  kc := public.sem_acento_0009(v_completo);
  -- RH: o mesmo nome completo; senão, o único funcionário ativo cujo nome começa por ele
  select count(*) into n from public.modulo_docs m
   where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
     and public.sem_acento_0009(m.dados ->> 'nome') = kc;
  if n = 1 then
    select m.dados into rh from public.modulo_docs m
     where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
       and public.sem_acento_0009(m.dados ->> 'nome') = kc;
  elsif n = 0 then
    select count(*) into n from public.modulo_docs m
     where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
       and left(public.sem_acento_0009(m.dados ->> 'nome'), length(kc) + 1) = kc || ' ';
    if n = 1 then
      select m.dados into rh from public.modulo_docs m
       where m.modulo = 'uniformes' and m.caminho = 'funcionarios' and coalesce(m.dados ->> 'ativo', 'true') <> 'false'
         and left(public.sem_acento_0009(m.dados ->> 'nome'), length(kc) + 1) = kc || ' ';
    end if;
  end if;
  v_cargo := case eq ->> 'cargo' when 'diretor' then 'Diretor' when 'gerente' then 'Gerente' when 'coordenador' then 'Coordenador'
    when 'supervisor' then 'Supervisor' when 'executiva' then 'Executiva' when 'executiva_comercial' then 'Executiva'
    when 'analista' then 'Analista' when 'assistente' then 'Assistente' when 'lider' then 'Líder'
    when 'operador' then 'Operador' else '' end;
  v_turno := case coalesce(rh -> 'rh' ->> 'turno', '') when 'desc1' then 'Desc 1 (6x1)' when 'desc2' then 'Desc 2 (6x1)' when 'desc3' then 'Desc 3 (5x2)'
    when 'galao-dia' then 'Galão · turno dia' when 'galao-noite' then 'Galão · turno noite' when 'adm' then 'Administrativo'
    when 'especial' then 'Horário especial' else '' end;
  -- pessoas aparecem com o primeiro nome; setores, motoristas e representantes, como estão no acesso
  v_curto := case when v_papel in ('mestre', 'equipe') then (regexp_split_to_array(v_completo, '\s+'))[1] else v_nome end;
  return jsonb_build_object(
    'nome', coalesce(nullif(v_curto, ''), v_nome),
    'nomeCompleto', v_completo,
    'papel', v_papel,
    'funcao', coalesce(nullif(concat_ws(' · ', nullif(v_cargo, ''), nullif(btrim(coalesce(eq ->> 'area', '')), '')), ''), nullif(btrim(rh ->> 'funcao'), ''), ''),
    'funcaoRh', coalesce(nullif(btrim(rh ->> 'funcao'), ''), ''),
    'turno', v_turno,
    'setor', coalesce(nullif(eq ->> 'area', ''), nullif(btrim(rh ->> 'setor'), ''), ''),
    'cargo', v_cargo,
    'admissao', coalesce(nullif(btrim(rh ->> 'admissao'), ''), ''));
end;
$$;
revoke execute on function public.minha_identificacao() from public, anon;
grant execute on function public.minha_identificacao() to authenticated;
