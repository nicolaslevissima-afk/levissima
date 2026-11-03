-- LEVÍSSIMA · 0036: histórico e lixeira (pedido de 29/10/2026).
--
-- * auditoria: cada alteração e cada exclusão nas tabelas docs (app principal) e modulo_docs (Manutenção,
--   Empilhadeiras, Uniformes e Garrafões) fica registrada com quem fez (do token) e quando.
--   - alterou: só os campos que mudaram, com o valor de antes (campos novos ficam na lista "campos" sem valor antigo);
--   - apagou: o documento inteiro, para restaurar.
--   Ficam de fora o rastreio de posição (muda o tempo todo) e as marcas internas (meta).
-- * Só a senha mestre (e a diretoria, que vê tudo) lê; só a senha mestre restaura (auditoria_restaurar):
--   devolve o documento apagado ou desfaz a alteração. A restauração também fica no histórico.
-- * rotulo: o nome do item (nome, título, cliente, descrição...) para achar na lista. O registro nunca impede a gravação.
-- (aplicada em partes: 0036a…0036g)
-- * Guardado por 90 dias: a limpeza dos mais antigos é feita pela função "acesso" (no login), sem apagar nada daqui.

create table if not exists public.auditoria (
  id bigserial primary key,
  em timestamptz not null default now(),
  tabela text not null,
  escopo text not null,
  chave text not null,
  acao text not null,
  antes jsonb not null default '{}'::jsonb,
  campos text[] not null default '{}',
  quem_ref text not null default '',
  quem_nome text not null default '',
  quem_papel text not null default '',
  restaurado_em timestamptz,
  restaurado_por text not null default '',
  rotulo text not null default ''
);
create index if not exists auditoria_em on public.auditoria (em desc);
create index if not exists auditoria_doc on public.auditoria (tabela, escopo, chave, em desc);
alter table public.auditoria enable row level security;
revoke all on public.auditoria from public, anon;
grant select on public.auditoria to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'auditoria' and policyname = 'auditoria_le_0036') then
    create policy "auditoria_le_0036" on public.auditoria for select to authenticated
      using ((select public.papel_atual()) = 'mestre');
  end if;
end $$;

create or replace function public.auditoria_rotulo_0036(d jsonb)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select left(coalesce(nullif(d ->> 'nome', ''), nullif(d ->> 'titulo', ''), nullif(d ->> 'cliente', ''),
                       case when jsonb_typeof(d -> 'clientes') = 'array' then nullif(d -> 'clientes' -> 0 ->> 'cliente', '') end,
                       nullif(d ->> 'descricao', ''), nullif(d ->> 'ponto', ''), nullif(d ->> 'produtoNome', ''), nullif(d ->> 'motorista', ''), ''), 120)
      || case when coalesce(d ->> 'data', '') ~ '^\d{4}-\d{2}-\d{2}'
              then ' · ' || substr(d ->> 'data', 9, 2) || '/' || substr(d ->> 'data', 6, 2) || '/' || substr(d ->> 'data', 1, 4) else '' end;
$$;

create or replace function public.auditoria_registrar_0036()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old jsonb := to_jsonb(old);
  v_new jsonb;
  d_old jsonb; d_new jsonb;
  v_escopo text;
  v_antes jsonb := '{}'::jsonb;
  v_campos text[] := '{}';
  k text;
  v_meta jsonb := coalesce(auth.jwt() -> 'app_metadata', '{}'::jsonb);
begin
  begin
    if tg_table_name = 'docs' then
      v_escopo := v_old ->> 'colecao';
      d_old := coalesce(v_old -> 'data', '{}'::jsonb);
    else
      v_escopo := (v_old ->> 'modulo') || '/' || (v_old ->> 'caminho');
      d_old := coalesce(v_old -> 'dados', '{}'::jsonb);
    end if;
    if v_escopo in ('rastreio', 'meta') then return null; end if;
    if jsonb_typeof(d_old) <> 'object' then d_old := jsonb_build_object('valor', d_old); end if;
    if tg_op = 'UPDATE' then
      v_new := to_jsonb(new);
      d_new := coalesce(case when tg_table_name = 'docs' then v_new -> 'data' else v_new -> 'dados' end, '{}'::jsonb);
      if jsonb_typeof(d_new) <> 'object' then d_new := jsonb_build_object('valor', d_new); end if;
      for k in select x from (select jsonb_object_keys(d_old) x union select jsonb_object_keys(d_new)) t loop
        if k in ('atualizadoEm', 'atualizado_em') then continue; end if;
        if (d_old -> k) is distinct from (d_new -> k) then
          v_campos := v_campos || k;
          if d_old ? k then v_antes := v_antes || jsonb_build_object(k, d_old -> k); end if;
        end if;
      end loop;
      if cardinality(v_campos) = 0 then return null; end if;
    else
      v_antes := d_old;
    end if;
    insert into public.auditoria (tabela, escopo, chave, acao, antes, campos, quem_ref, quem_nome, quem_papel, rotulo)
    values (tg_table_name, v_escopo, v_old ->> 'id', case when tg_op = 'UPDATE' then 'alterou' else 'apagou' end, v_antes, v_campos,
            coalesce(v_meta ->> 'ref', case when auth.uid() is null then 'sistema' else '' end), coalesce(v_meta ->> 'nome', ''), coalesce(v_meta ->> 'papel', ''),
            public.auditoria_rotulo_0036(case when tg_op = 'UPDATE' then d_new else d_old end));
  exception when others then
    -- o histórico nunca impede a gravação: se algo der errado aqui, só não registra
    raise warning 'auditoria: %', sqlerrm;
  end;
  return null;
end $$;
revoke execute on function public.auditoria_registrar_0036() from public, anon, authenticated;

create or replace trigger auditoria_docs_0036 after update or delete on public.docs
  for each row execute function public.auditoria_registrar_0036();
create or replace trigger auditoria_modulo_docs_0036 after update or delete on public.modulo_docs
  for each row execute function public.auditoria_registrar_0036();

-- Restaurar: devolve o documento apagado ou desfaz a alteração (só a senha mestre)
create or replace function public.auditoria_restaurar(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a public.auditoria%rowtype;
  v_mod text; v_cam text;
  v_atual jsonb; v_novo jsonb;
  k text;
begin
  if not (coalesce(public.papel_atual(), '') = 'mestre' and not public.so_inclui()) then raise exception 'permissao'; end if;
  select * into a from public.auditoria where id = p_id;
  if not found then raise exception 'nao_encontrado'; end if;
  if a.tabela = 'modulo_docs' then
    v_mod := split_part(a.escopo, '/', 1);
    v_cam := substr(a.escopo, length(v_mod) + 2);
    select dados into v_atual from public.modulo_docs where modulo = v_mod and caminho = v_cam and id = a.chave;
  else
    select data into v_atual from public.docs where colecao = a.escopo and id = a.chave;
  end if;
  if a.acao = 'apagou' then
    if v_atual is not null then raise exception 'ja_existe'; end if;
    if a.tabela = 'modulo_docs' then
      insert into public.modulo_docs (modulo, caminho, id, dados) values (v_mod, v_cam, a.chave, a.antes);
    else
      insert into public.docs (colecao, id, data) values (a.escopo, a.chave, a.antes);
    end if;
  else
    if v_atual is null then raise exception 'apagado'; end if;
    v_novo := v_atual || a.antes;
    foreach k in array a.campos loop
      if not (a.antes ? k) then v_novo := v_novo - k; end if;
    end loop;
    if a.tabela = 'modulo_docs' then
      update public.modulo_docs set dados = v_novo, atualizado_em = now() where modulo = v_mod and caminho = v_cam and id = a.chave;
    else
      update public.docs set data = v_novo, atualizado_em = now() where colecao = a.escopo and id = a.chave;
    end if;
  end if;
  update public.auditoria set restaurado_em = now(), restaurado_por = coalesce(public.ref_atual(), '') where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.auditoria_restaurar(bigint) from public, anon;
grant execute on function public.auditoria_restaurar(bigint) to authenticated;
