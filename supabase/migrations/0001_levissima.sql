-- LEVÍSSIMA · banco de dados no Supabase
-- Uma tabela guarda tudo: cada linha é um "documento" (coleção + id) com os dados em JSON.
-- As regras de acesso (só quem entrou com senha) estão em 0002_acesso.sql.

create table if not exists public.docs (
  colecao text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(),
  primary key (colecao, id)
);
alter table public.docs replica identity full;

-- RLS ligada desde o início: sem as políticas de 0002_acesso.sql, ninguém lê nem grava nada.
alter table public.docs enable row level security;
revoke all on public.docs from public, anon;

-- tempo real: as telas se atualizam sozinhas quando outro aparelho grava
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;

-- junta dois JSON "por dentro": objetos se misturam, o resto é substituído
create or replace function public.jsonb_mesclar(a jsonb, b jsonb)
returns jsonb
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  k text;
  v jsonb;
  r jsonb;
begin
  if b is null then return a; end if;
  if a is null or jsonb_typeof(a) <> 'object' or jsonb_typeof(b) <> 'object' then return b; end if;
  r := a;
  for k, v in select * from jsonb_each(b) loop
    if r ? k and jsonb_typeof(r -> k) = 'object' and jsonb_typeof(v) = 'object' then
      r := jsonb_set(r, array[k], public.jsonb_mesclar(r -> k, v));
    else
      r := jsonb_set(r, array[k], v);
    end if;
  end loop;
  return r;
end $$;

-- grava um documento inteiro (ou mistura com o que já existe) e, se pedido, acrescenta itens a listas
-- sem repetir. Devolve como o documento ficou.
create or replace function public.doc_gravar(
  p_colecao text, p_id text, p_dados jsonb,
  p_mesclar boolean default false, p_uniao jsonb default null
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  atual jsonb;
  novo jsonb;
  k text;
  itens jsonb;
  item jsonb;
begin
  select data into atual from public.docs where colecao = p_colecao and id = p_id for update;
  if p_mesclar and atual is not null then
    novo := public.jsonb_mesclar(atual, coalesce(p_dados, '{}'::jsonb));
  else
    novo := coalesce(p_dados, '{}'::jsonb);
  end if;
  if p_uniao is not null and jsonb_typeof(p_uniao) = 'object' then
    for k, itens in select * from jsonb_each(p_uniao) loop
      if not (novo ? k) or jsonb_typeof(novo -> k) <> 'array' then
        novo := jsonb_set(novo, array[k], '[]'::jsonb);
      end if;
      for item in select * from jsonb_array_elements(itens) loop
        if not ((novo -> k) @> jsonb_build_array(item)) then
          novo := jsonb_set(novo, array[k], (novo -> k) || jsonb_build_array(item));
        end if;
      end loop;
    end loop;
  end if;
  insert into public.docs (colecao, id, data, atualizado_em)
  values (p_colecao, p_id, novo, now())
  on conflict (colecao, id) do update set data = excluded.data, atualizado_em = now();
  return novo;
end $$;

-- muda só os campos enviados; o documento precisa existir
create or replace function public.doc_atualizar(p_colecao text, p_id text, p_dados jsonb)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  novo jsonb;
begin
  update public.docs
     set data = data || coalesce(p_dados, '{}'::jsonb), atualizado_em = now()
   where colecao = p_colecao and id = p_id
  returning data into novo;
  if not found then
    raise exception 'Documento não existe: %/%', p_colecao, p_id using errcode = 'P0002';
  end if;
  return novo;
end $$;

-- várias gravações juntas: ou todas acontecem, ou nenhuma
create or replace function public.docs_lote(p_ops jsonb)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  op jsonb;
  novo jsonb;
  res jsonb := '[]'::jsonb;
begin
  for op in select * from jsonb_array_elements(p_ops) loop
    if op ->> 'op' = 'delete' then
      delete from public.docs where colecao = op ->> 'colecao' and id = op ->> 'id';
      novo := null;
    elsif op ->> 'op' = 'update' then
      novo := public.doc_atualizar(op ->> 'colecao', op ->> 'id', op -> 'dados');
    else
      novo := public.doc_gravar(op ->> 'colecao', op ->> 'id', op -> 'dados',
                                coalesce((op ->> 'mesclar')::boolean, false), op -> 'uniao');
    end if;
    res := res || jsonb_build_array(jsonb_build_object('colecao', op ->> 'colecao', 'id', op ->> 'id', 'data', novo));
  end loop;
  return res;
end $$;

revoke execute on function public.jsonb_mesclar(jsonb, jsonb) from public, anon;
revoke execute on function public.doc_gravar(text, text, jsonb, boolean, jsonb) from public, anon;
revoke execute on function public.doc_atualizar(text, text, jsonb) from public, anon;
revoke execute on function public.docs_lote(jsonb) from public, anon;
grant execute on function public.jsonb_mesclar(jsonb, jsonb) to authenticated;
grant execute on function public.doc_gravar(text, text, jsonb, boolean, jsonb) to authenticated;
grant execute on function public.doc_atualizar(text, text, jsonb) to authenticated;
grant execute on function public.docs_lote(jsonb) to authenticated;
