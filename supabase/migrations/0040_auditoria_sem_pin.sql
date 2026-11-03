-- LEVÍSSIMA · 0040: o histórico (auditoria) nunca guarda o hash do PIN (03/11/2026).
-- A 0035 tira o pinHash dos documentos da equipe; essa alteração (e qualquer outra antiga) não pode deixar o hash
-- guardado no histórico, que a diretoria também lê. Aplicada antes da 0035; o registro antigo que tinha o campo foi limpo.

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
    d_old := d_old - 'pinHash';
    if tg_op = 'UPDATE' then
      v_new := to_jsonb(new);
      d_new := coalesce(case when tg_table_name = 'docs' then v_new -> 'data' else v_new -> 'dados' end, '{}'::jsonb);
      if jsonb_typeof(d_new) <> 'object' then d_new := jsonb_build_object('valor', d_new); end if;
      d_new := d_new - 'pinHash';
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
    raise warning 'auditoria: %', sqlerrm;
  end;
  return null;
end $$;
revoke execute on function public.auditoria_registrar_0036() from public, anon, authenticated;

update public.auditoria set antes = antes - 'pinHash', campos = array_remove(campos, 'pinHash')
 where antes ? 'pinHash' or 'pinHash' = any (campos);
