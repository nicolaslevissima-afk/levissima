-- LEVÍSSIMA · 0017: cargo "Executiva comercial" no organograma (Cadastros › Equipe com senha), pedido de 19/10/2026.
-- A identificação automática (minha_identificacao, usada nos chamados da Manutenção) passa a escrever esse cargo.
-- Mesma função da 0013, só com o cargo novo.

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
    when 'operador' then 'Operador' when 'executiva_comercial' then 'Executiva comercial' else '' end;
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
