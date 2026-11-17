-- LEVÍSSIMA · 0055: as 10 máquinas dos tablets (pedido de 17/11/2026), depois da versão do app que as usa.
-- * Linha 2: as 6 máquinas que já existiam ganham id e acesso ('setor:maq-l2-...').
-- * Linha 1: Sopradora, Envase 1, Rotuladora e Empacotadora, com a unidade copiada das máquinas iguais da Linha 2 e a
--   marca "confirmar" (o PCP confere em PCP › Linhas e turnos); a etapa final da Linha 1 fica para o PCP escolher.
-- * Só completa o que falta (pode rodar de novo sem mudar nada).

do $$
declare d jsonb; ls jsonb; l jsonb; ms jsonb; m jsonb; i int; j int; slug text;
begin
  select data into d from public.docs where colecao = 'mp-config' and id = 'linhas-producao';
  if d is null or jsonb_typeof(d -> 'linhas') <> 'array' then return; end if;
  ls := d -> 'linhas';
  for i in 0 .. jsonb_array_length(ls) - 1 loop
    l := ls -> i;
    ms := case when jsonb_typeof(l -> 'maquinas') = 'array' then l -> 'maquinas' else '[]'::jsonb end;
    if l ->> 'id' = 'l1' and jsonb_array_length(ms) = 0 then
      -- Linha 1: unidade copiada das máquinas iguais da Linha 2, para o PCP confirmar; etapa final a escolher
      ms := '[{"id": "l1-sopradora", "nome": "Sopradora", "unidade": "garrafas", "acesso": "setor:maq-l1-sopradora", "confirmar": true},
              {"id": "l1-envase-1", "nome": "Envase 1", "unidade": "garrafas", "acesso": "setor:maq-l1-envase-1", "confirmar": true},
              {"id": "l1-rotuladora", "nome": "Rotuladora", "unidade": "garrafas", "acesso": "setor:maq-l1-rotuladora", "confirmar": true},
              {"id": "l1-empacotadora", "nome": "Empacotadora", "unidade": "fardos", "acesso": "setor:maq-l1-empacotadora", "confirmar": true}]'::jsonb;
    else
      for j in 0 .. jsonb_array_length(ms) - 1 loop
        m := ms -> j;
        if coalesce(m ->> 'id', '') = '' and coalesce(m ->> 'nome', '') <> '' then
          slug := (case l ->> 'id' when 'linha2' then 'l2' else l ->> 'id' end) || '-' ||
                  trim(both '-' from regexp_replace(lower(translate(m ->> 'nome', 'áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ', 'aaaaeeiooouucAAAAEEIOOOUUC')), '[^a-z0-9]+', '-', 'g'));
          m := m || jsonb_build_object('id', slug);
          if coalesce(m ->> 'acesso', '') = '' then m := m || jsonb_build_object('acesso', 'setor:maq-' || slug); end if;
          ms := jsonb_set(ms, array[j::text], m);
        end if;
      end loop;
    end if;
    ls := jsonb_set(ls, array[i::text], jsonb_set(l, '{maquinas}', ms));
  end loop;
  update public.docs set data = jsonb_set(d, '{linhas}', ls) || jsonb_build_object('atualizadoEm', public.maq_iso_0054(now()), 'atualizadoPor', 'migração 0054 (máquinas dos tablets)'),
         atualizado_em = now()
   where colecao = 'mp-config' and id = 'linhas-producao';
end $$;
