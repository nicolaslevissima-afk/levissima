-- LEVÍSSIMA · 0065 (27/11/2026)
-- 1. Compras (solicitação 29): quem autoriza o pedido altera o pedido que espera a autorização, mesmo com todas as abas
--    "só inclui", sempre com o motivo da alteração (edicao.motivo, 3 letras ou mais). Quem autoriza: Compras, quem
--    aprova e a diretoria; coordenador, supervisor ou gerente do setor (0047/0063: setores marcados ou, em branco, a
--    área); o substituto de um gestor ausente hoje. Só com a ordem em "pedido" e sem mudar o status, quem pediu, o
--    número, a data nem cancelar. A 0058 (assinar as etapas) e a 0059 (quem pediu edita e cancela) continuam iguais.
-- 2. Novidades do Início: cada acesso guarda nas preferências (0047) as novidades que já viu (chave "novidades": até 200
--    códigos curtos com a data em que viu), para elas sumirem em todos os aparelhos da pessoa.

-- quem autoriza este pedido (com o acesso de quem grava)
create or replace function public.oc_autoriza_0065(d jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  r text := coalesce(public.ref_atual(), '');
  eid text := '';
  m jsonb;
  g jsonb;
  a jsonb;
  gid text;
  setor text := public.sem_acento_0009(d ->> 'setor');
  hoje text;
begin
  if r like 'escritorio:%' then eid := substr(r, 12); end if;
  if eid = '' then return false; end if;
  select data into m from public.docs where colecao = 'equipe' and id = eid;
  if m is null then return false; end if;
  if m -> 'compras' = 'true'::jsonb or m -> 'aprovaCompra' = 'true'::jsonb or m ->> 'cargo' = 'diretor' then return true; end if;
  if public.oc_setor_visivel_0047(m, 'pedido', setor) then return true; end if;
  hoje := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
  for a in
    select data from public.docs
     where colecao = 'compras-ausencias' and data ->> 'substitutoId' = eid
       and coalesce(data ->> 'encerradaEm', '') = '' and data ->> 'de' <= hoje and data ->> 'ate' >= hoje
  loop
    gid := coalesce(a ->> 'gestorId', '');
    if gid = '' or gid = eid then continue; end if;
    select data into g from public.docs where colecao = 'equipe' and id = gid;
    if g is not null and public.oc_setor_visivel_0047(g, 'pedido', setor) then return true; end if;
  end loop;
  return false;
end $$;
revoke execute on function public.oc_autoriza_0065(jsonb) from public, anon, authenticated;

create or replace function public.oc_so_inclui_0058()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
  v_r text;
  v_dono boolean;
begin
  if new.colecao <> 'compras-ordens' or tg_op <> 'UPDATE' then return new; end if;
  if auth.jwt() is null then return new; end if; -- manutenção direta no banco
  if not public.so_inclui() or coalesce(public.papel_atual(), '') <> 'equipe' then return new; end if;

  v_r := coalesce(public.ref_atual(), '');
  v_dono := v_r <> '' and (coalesce(old.data -> 'pedido' ->> 'ref', '') = v_r
    or (v_r like 'escritorio:%' and coalesce(old.data -> 'pedido' ->> 'id', '') = substr(v_r, 12)));

  if v_dono then
    foreach k in array array['pedido', 'numero', 'criadoEm'] loop
      if (new.data -> k) is distinct from (old.data -> k) then
        raise exception 'so_inclui' using errcode = '42501';
      end if;
    end loop;
    if coalesce(new.data ->> 'status', '') = 'cancelada' and coalesce(old.data ->> 'status', '') <> 'cancelada'
       and length(btrim(coalesce(new.data -> 'cancelamento' ->> 'motivo', ''))) < 3 then
      raise exception 'Escreva o motivo do cancelamento.';
    end if;
    if ((new.data -> 'itens') is distinct from (old.data -> 'itens') or (new.data -> 'setor') is distinct from (old.data -> 'setor')
        or (new.data -> 'urgencia') is distinct from (old.data -> 'urgencia') or (new.data -> 'obs') is distinct from (old.data -> 'obs'))
       and length(btrim(coalesce(new.data -> 'edicao' ->> 'motivo', ''))) < 3 then
      raise exception 'Escreva o motivo da alteração.';
    end if;
    return new;
  end if;

  -- quem autoriza: altera o pedido que espera a autorização, com o motivo (0065)
  if coalesce(old.data ->> 'status', '') = 'pedido' and coalesce(new.data ->> 'status', '') = 'pedido' and public.oc_autoriza_0065(old.data) then
    foreach k in array array['pedido', 'numero', 'criadoEm', 'cancelamento', 'canceladaEm', 'canceladaPor'] loop
      if (new.data -> k) is distinct from (old.data -> k) then
        raise exception 'so_inclui' using errcode = '42501';
      end if;
    end loop;
    if ((new.data -> 'itens') is distinct from (old.data -> 'itens') or (new.data -> 'setor') is distinct from (old.data -> 'setor')
        or (new.data -> 'urgencia') is distinct from (old.data -> 'urgencia') or (new.data -> 'obs') is distinct from (old.data -> 'obs'))
       and length(btrim(coalesce(new.data -> 'edicao' ->> 'motivo', ''))) < 3 then
      raise exception 'Escreva o motivo da alteração.';
    end if;
    return new;
  end if;

  foreach k in array array['itens', 'setor', 'urgencia', 'obs', 'pedido', 'numero', 'criadoEm', 'edicao', 'edicoes', 'cancelamento', 'canceladaEm', 'canceladaPor'] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'so_inclui' using errcode = '42501';
    end if;
  end loop;
  if coalesce(new.data ->> 'status', '') = 'cancelada' and coalesce(old.data ->> 'status', '') <> 'cancelada' then
    raise exception 'so_inclui' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function public.oc_so_inclui_0058() from public, anon, authenticated;

-- preferências do próprio acesso: "abas" (0047) e "novidades" (0065)
create or replace function public.preferencia_gravar(p_chave text, p_valor jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.preferencias;
begin
  if not public.chat_pode_0019() then raise exception 'permissao' using errcode = '42501'; end if;
  if p_chave is null or p_chave not in ('abas', 'novidades') then raise exception 'chave' using errcode = '22023'; end if;
  if p_valor is null or jsonb_typeof(p_valor) = 'null' then
    update public.preferencias set dados = dados - p_chave, atualizado_em = now() where dono = public.ref_atual() returning * into r;
    return coalesce(to_jsonb(r), '{}'::jsonb);
  end if;
  if p_chave = 'abas' then
    -- abas: lista de até 80 nomes curtos (ex.: "cargas", "mod:manutencao")
    if jsonb_typeof(p_valor) <> 'array' or jsonb_array_length(p_valor) > 80
       or exists (select 1 from jsonb_array_elements(p_valor) x where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9:_-]{1,40}$') then
      raise exception 'valor' using errcode = '22023';
    end if;
  else
    -- novidades vistas: { "código curto": "data em que viu" }, até 200
    if jsonb_typeof(p_valor) <> 'object' or (select count(*) from jsonb_object_keys(p_valor)) > 200
       or exists (select 1 from jsonb_each(p_valor) x where x.key !~ '^[a-z0-9]{1,16}$' or jsonb_typeof(x.value) <> 'string' or length(x.value #>> '{}') > 30) then
      raise exception 'valor' using errcode = '22023';
    end if;
  end if;
  insert into public.preferencias (dono, dados, atualizado_em) values (public.ref_atual(), jsonb_build_object(p_chave, p_valor), now())
  on conflict (dono) do update set dados = public.preferencias.dados || excluded.dados, atualizado_em = now()
  returning * into r;
  return to_jsonb(r);
end $$;
revoke execute on function public.preferencia_gravar(text, jsonb) from public, anon;
grant execute on function public.preferencia_gravar(text, jsonb) to authenticated;
