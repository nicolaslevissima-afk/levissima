-- LEVÍSSIMA · 0052: PCP, etapa 1 (pedido de 12/11/2026).
-- * Permissão "Configura o PCP" (configuraPcp em Cadastros › Equipe): além da senha mestre, quem tem essa permissão
--   grava a configuração das linhas (mp-config/linhas-producao): horário dos turnos, dias, pausas, exceções do
--   calendário e capacidade de planejamento. O nome, a unidade, os produtos, as máquinas e a lista de linhas
--   continuam só da senha mestre, e os turnos que já existem não somem nem mudam de nome (o gatilho
--   pcp_linhas_guarda_0052 confere).
-- * O documento das linhas passa a existir no banco com as mesmas linhas que o app já usava (sem nenhum horário,
--   capacidade ou turno novo): antes ele só existia no código.
-- * A programação (rascunho, blocos de manutenção e versões confirmadas) fica nas coleções que já existem
--   (producao-ordens e producao-eventos), com as regras de sempre: só o escritório (senha mestre e equipe) lê e grava.

create or replace function public.pcp_configura_0052()
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
  return coalesce(m -> 'configuraPcp' = 'true'::jsonb, false);
end $$;
revoke execute on function public.pcp_configura_0052() from public, anon;
grant execute on function public.pcp_configura_0052() to authenticated;

-- nome de um turno (o cadastro antigo guardava só o texto)
create or replace function public.pcp_turno_nome_0052(t jsonb)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$ select case when jsonb_typeof(t) = 'string' then t #>> '{}' when jsonb_typeof(t) = 'object' then coalesce(t ->> 'nome', '') else '' end; $$;
revoke execute on function public.pcp_turno_nome_0052(jsonb) from public, anon, authenticated;

create or replace function public.pcp_linhas_guarda_0052()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  lo jsonb; ln jsonb; a jsonb; b jsonb; i int; nome text;
begin
  -- só quem entra pela senha da equipe tem a regra (a senha mestre muda tudo)
  if coalesce(public.papel_atual(), '') <> 'equipe' then return new; end if;
  if tg_op = 'INSERT' then
    if exists (select 1 from public.docs where colecao = new.colecao and id = new.id) then return new; end if; -- vira atualização
    raise exception 'pcp: só a senha mestre cria a configuração das linhas';
  end if;
  lo := coalesce(old.data -> 'linhas', '[]'::jsonb);
  ln := coalesce(new.data -> 'linhas', '[]'::jsonb);
  if jsonb_typeof(ln) <> 'array' or jsonb_typeof(lo) <> 'array' or jsonb_array_length(ln) <> jsonb_array_length(lo) then
    raise exception 'pcp: só a senha mestre inclui ou tira linhas';
  end if;
  for i in 0 .. jsonb_array_length(lo) - 1 loop
    a := lo -> i; b := ln -> i;
    if (a -> 'id') is distinct from (b -> 'id') or (a -> 'nome') is distinct from (b -> 'nome') or (a -> 'un') is distinct from (b -> 'un')
       or (a -> 'produtos') is distinct from (b -> 'produtos') or (a -> 'maquinas') is distinct from (b -> 'maquinas')
       or (a -> 'op') is distinct from (b -> 'op') or (a -> 'metaId') is distinct from (b -> 'metaId') then
      raise exception 'pcp: só a senha mestre muda o nome, a unidade, os produtos e as máquinas da linha';
    end if;
    for nome in select public.pcp_turno_nome_0052(t) from jsonb_array_elements(coalesce(a -> 'turnos', '[]'::jsonb)) t loop
      if nome <> '' and not exists (select 1 from jsonb_array_elements(coalesce(b -> 'turnos', '[]'::jsonb)) t2 where public.pcp_turno_nome_0052(t2) = nome) then
        raise exception 'pcp: o turno % não pode sumir nem mudar de nome (só a senha mestre)', nome;
      end if;
    end loop;
  end loop;
  return new;
end $$;
revoke execute on function public.pcp_linhas_guarda_0052() from public, anon, authenticated;

drop trigger if exists pcp_linhas_guarda_0052 on public.docs;
create trigger pcp_linhas_guarda_0052 before insert or update on public.docs
  for each row when (new.colecao = 'mp-config' and new.id = 'linhas-producao') execute function public.pcp_linhas_guarda_0052();

-- a configuração das linhas: senha mestre ou "Configura o PCP" (apagar continua só da senha mestre)
alter policy "producao_cadastro_grava" on public.docs
  with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
              or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052())));
alter policy "producao_cadastro_altera" on public.docs
  using (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
         or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052())))
  with check (not public.colecao_cadastro_producao(colecao) or (select public.papel_atual()) = 'mestre'
              or (colecao = 'mp-config' and id = 'linhas-producao' and (select public.pcp_configura_0052())));

-- as linhas que o app já usava (PH_LINHAS_PADRAO), agora gravadas no banco; não muda nada se já existir
insert into public.docs (colecao, id, data)
values ('mp-config', 'linhas-producao', jsonb_build_object(
  'linhas', '[
    {"id": "l1", "nome": "Linha 1", "metaId": "l1", "un": "fardos", "turnos": [], "produtos": ["1,5L natural", "1,5L com gás", "350ml natural", "350ml com gás"], "maquinas": []},
    {"id": "linha2", "nome": "Linha 2", "metaId": "l2", "un": "fardos", "turnos": ["DESC 1", "DESC 2", "DESC 3"], "produtos": ["510ml natural", "510ml com gás"], "maquinas": [
      {"nome": "Sopradora 2A", "unidade": "garrafas", "obrigatoria": true}, {"nome": "Sopradora 2B", "unidade": "garrafas"},
      {"nome": "Enchedora", "unidade": "garrafas", "obrigatoria": true}, {"nome": "Rotuladora 2", "unidade": "garrafas", "obrigatoria": true},
      {"nome": "Rotuladora 3", "unidade": "garrafas", "obrigatoria": true}, {"nome": "Empacotadora", "unidade": "fardos", "obrigatoria": true, "producao": true}]},
    {"id": "g6", "nome": "Linha 6 L", "metaId": "g6", "un": "galões", "turnos": [], "produtos": ["6L"], "maquinas": []},
    {"id": "g10", "nome": "Linha 10 L", "metaId": "g10", "un": "galões", "turnos": [], "produtos": ["10L"], "maquinas": []},
    {"id": "copo", "nome": "Copos", "metaId": "copo", "un": "caixas", "turnos": [], "produtos": ["Copo 200ml (24 un)", "Copo 200ml (48 un)", "Copo 300ml"], "maquinas": []},
    {"id": "retornavel", "nome": "Retornável", "op": false, "turnos": ["Retornável 1 (dia)", "Retornável 2 (noite)"], "produtos": [], "maquinas": []}
  ]'::jsonb,
  'atualizadoEm', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'atualizadoPor', 'migração 0052 (as linhas que o app já usava)'))
on conflict (colecao, id) do nothing;
