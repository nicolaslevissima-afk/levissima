-- LEVÍSSIMA · teste da 0064 (histórico de permissões): só a senha mestre lê e grava; ninguém altera nem apaga.
-- Rodar: createdb t && psql -d t -f testes/turnos-banco.sql && psql -d t -f testes/permissoes-banco.sql
--        && psql -d t -f supabase/migrations/0064_historico_de_permissoes.sql && psql -d t -f testes/permissoes-sql.sql
\set ON_ERROR_STOP 1
create or replace function pg_temp.como(p text, r text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('app_metadata', json_build_object('papel', p, 'ref', r))::text, true); $$;
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$
begin if not c then raise exception 'FALHOU: %', m; end if; raise notice 'ok: %', m; end $$;

begin;
set local role authenticated;
-- senha mestre grava pelo doc_gravar (como o app) com o carimbo dela
select pg_temp.como('mestre', 'mestre');
select public.doc_gravar('permissoes-historico', 'ph1', '{"porRef":"mestre","pessoa":"Teste","mudancas":[{"f":"Aba Cargas","de":"—","para":"Edita"}]}'::jsonb);
select pg_temp.ok((select count(*) from public.docs where colecao = 'permissoes-historico') = 1, 'senha mestre grava');
-- diretoria (papel mestre) grava com o carimbo dela
select pg_temp.como('mestre', 'diretoria:d1');
select public.doc_gravar('permissoes-historico', 'ph2', '{"porRef":"diretoria:d1","pessoa":"Teste"}'::jsonb);
select pg_temp.ok((select count(*) from public.docs where colecao = 'permissoes-historico') = 2, 'diretoria grava com o próprio carimbo');
commit;

-- carimbo de outro: recusado
begin;
set local role authenticated;
select pg_temp.como('mestre', 'diretoria:d1');
do $$ begin
  perform public.doc_gravar('permissoes-historico', 'ph3', '{"porRef":"mestre"}'::jsonb);
  raise exception 'FALHOU: gravou com o carimbo de outro';
exception when insufficient_privilege then raise notice 'ok: carimbo de outro recusado';
end $$;
rollback;

-- ninguém altera (nem a senha mestre)
begin;
set local role authenticated;
select pg_temp.como('mestre', 'mestre');
do $$ begin
  perform public.doc_gravar('permissoes-historico', 'ph1', '{"porRef":"mestre","pessoa":"Mudado"}'::jsonb);
  raise exception 'FALHOU: alterou o registro';
exception when insufficient_privilege then raise notice 'ok: senha mestre não altera';
end $$;
rollback;
begin;
set local role authenticated;
select pg_temp.como('mestre', 'mestre');
update public.docs set data = data || '{"pessoa":"x"}' where colecao = 'permissoes-historico';
select pg_temp.ok((select count(*) from public.docs where colecao = 'permissoes-historico' and data ->> 'pessoa' = 'x') = 0, 'update direto não muda nada');
delete from public.docs where colecao = 'permissoes-historico';
select pg_temp.ok((select count(*) from public.docs where colecao = 'permissoes-historico') = 2, 'ninguém apaga (nem a senha mestre)');
commit;

-- equipe: não lê nem grava
begin;
set local role authenticated;
select pg_temp.como('equipe', 'escritorio:e1');
select pg_temp.ok((select count(*) from public.docs where colecao = 'permissoes-historico') = 0, 'equipe não lê o histórico');
do $$ begin
  perform public.doc_gravar('permissoes-historico', 'ph9', '{"porRef":"escritorio:e1"}'::jsonb);
  raise exception 'FALHOU: equipe gravou';
exception when insufficient_privilege then raise notice 'ok: equipe não grava';
end $$;
-- as outras coleções continuam normais para a equipe
select public.doc_gravar('qualquer', 'q1', '{"a":1}'::jsonb);
select public.doc_gravar('qualquer', 'q1', '{"a":2}'::jsonb);
select pg_temp.ok((select data ->> 'a' from public.docs where colecao = 'qualquer' and id = 'q1') = '2', 'outras coleções: grava e altera como antes');
rollback;
select 'TUDO OK' as resultado;
