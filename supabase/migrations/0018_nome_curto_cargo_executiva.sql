-- LEVÍSSIMA · 0018: nome completo no cadastro, primeiro nome no app; cargo "Executiva" (pedido de 19/10/2026).
-- Cadastros › Equipe com senha passa a guardar o NOME COMPLETO de cada pessoa (campo "nome" do documento da equipe).
-- No app a pessoa aparece só com o primeiro nome e o cargo na frente. A identificação automática (minha_identificacao,
-- usada nos chamados da Manutenção) acompanha:
--   * acha a pessoa no organograma pelo nome do acesso mesmo quando um dos dois é só o primeiro nome
--     (o único cadastro cujo nome completo começa pelo nome do acesso, ou o contrário);
--   * procura no RH pelo nome completo do organograma;
--   * devolve "nome" = primeiro nome (para senha mestre, diretoria e equipe) e "nomeCompleto";
--   * o cargo "executiva" (e o antigo "executiva_comercial", da 0017) sai como "Executiva";
--   * sem cargo, a função sai só com a área ("Faturamento"), sem o "· " solto do começo.
-- Mesma função da 0017 com essas mudanças.

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
  -- ... senão o único cadastro cujo nome completo começa pelo nome do acesso ("Angélica" → "Angélica Peres dos Santos")
  if eq is null then
    select count(*) into n from public.docs d
     where d.colecao = 'equipe' and left(public.sem_acento_0009(d.data ->> 'nome'), length(k) + 1) = k || ' ';
    if n = 1 then
      select d.data into eq from public.docs d
       where d.colecao = 'equipe' and left(public.sem_acento_0009(d.data ->> 'nome'), length(k) + 1) = k || ' ';
    end if;
  end if;
  -- ... senão o único cadastro cujo nome é o começo do nome do acesso ("Angélica Peres dos Santos" → "Angélica")
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
    'cargo', v_cargo);
end;
$$;
revoke execute on function public.minha_identificacao() from public, anon;
grant execute on function public.minha_identificacao() to authenticated;
