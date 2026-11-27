-- LEVÍSSIMA · teste da 0064: o que falta na simulação mínima (turnos-banco.sql) — apagar, só da senha mestre e o doc_gravar.
create policy apaga on public.docs for delete to authenticated using ((select public.papel_atual()) in ('mestre', 'equipe'));
create function public.colecao_so_mestre(p_colecao text) returns boolean language sql immutable as $$ select p_colecao in ('motorista-docs', 'representantes', 'representante-docs') $$;
create policy so_mestre on public.docs as restrictive for all to authenticated
  using (not public.colecao_so_mestre(colecao) or (select public.papel_atual()) = 'mestre')
  with check (not public.colecao_so_mestre(colecao) or (select public.papel_atual()) = 'mestre');
create or replace function public.doc_gravar(p_colecao text, p_id text, p_dados jsonb, p_mesclar boolean default false, p_uniao jsonb default null)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare atual jsonb; novo jsonb;
begin
  select data into atual from public.docs where colecao = p_colecao and id = p_id for update;
  novo := case when p_mesclar and atual is not null then atual || coalesce(p_dados, '{}'::jsonb) else coalesce(p_dados, '{}'::jsonb) end;
  insert into public.docs (colecao, id, data, atualizado_em) values (p_colecao, p_id, novo, now())
  on conflict (colecao, id) do update set data = excluded.data, atualizado_em = now();
  return novo;
end $$;
grant execute on function public.doc_gravar(text, text, jsonb, boolean, jsonb) to authenticated;
