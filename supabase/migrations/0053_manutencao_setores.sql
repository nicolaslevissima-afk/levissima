-- 0053 · Manutenção: o "Geral" separado por setor (pedido de 17/11/2026)
--
-- Os equipamentos que estavam em "Geral e utilidades" (linha UTIL do módulo Manutenção) passam para o setor onde
-- ficam: Sala de compressores (COMP), Reservatórios de ar (RESAR), Setor de Paletização (PALET) e Envases (ENV).
-- O Robô Paletizador, que estava na Linha 2, vai para o Setor de Paletização. O Carbonatador passa a se chamar
-- "Carbonatador RZ-CD-10". Os equipamentos da lista que ainda não existiam são cadastrados (sem TAG).
-- Só muda a linha (setor), a ordem e o nome: o id continua o mesmo, então chamados, planos, fichas, peças e o
-- histórico continuam ligados. As fichas acompanham o setor do equipamento. Pode rodar de novo sem duplicar.

do $$
declare
  agora bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  r record;
begin
  -- equipamentos que já existem: setor e ordem dentro do setor
  for r in
    select * from (values
      ('Booster BSCV nº 1', 'COMP', 1, null::text), ('Booster BSCV nº 2', 'COMP', 2, null), ('Booster BSCV nº 3', 'COMP', 3, null),
      ('Compressor Chicago nº 1', 'COMP', 4, null), ('Compressor Chicago nº 2', 'COMP', 5, null), ('Compressor Puma', 'COMP', 6, null),
      ('Secador de ar HE-500 nº 1', 'COMP', 7, null), ('Secador de ar HE-500 nº 2', 'COMP', 8, null),
      ('Reservatório de ar 1.000 L nº 1', 'RESAR', 1, null), ('Reservatório de ar 1.000 L nº 2', 'RESAR', 2, null),
      ('Reservatório de ar 1.000 L nº 3', 'RESAR', 3, null), ('Reservatório de ar 1.000 L nº 4', 'RESAR', 4, null),
      ('Robô Paletizador', 'PALET', 1, null), ('Envolvedora orbital automática', 'PALET', 2, null), ('Magazine de paletes', 'PALET', 3, null),
      ('Elevador de paletes', 'PALET', 4, null), ('Basculante PBR', 'PALET', 5, null),
      ('Strechadeira 1', 'PALET', 6, null), ('Strechadeira 2', 'PALET', 7, null), ('Strechadeira 3', 'PALET', 8, null),
      ('Carbonatador', 'ENV', 1, 'Carbonatador RZ-CD-10'), ('Carbonatador RZ-CD-10', 'ENV', 1, null)
    ) as v(nome, setor, ordem, novo_nome)
  loop
    update public.modulo_docs
       set dados = dados || jsonb_build_object('linha', r.setor, 'ordem', r.ordem, 'atualizadoEm', agora)
                         || case when r.novo_nome is not null then jsonb_build_object('nome', r.novo_nome) else '{}'::jsonb end,
           atualizado_em = now()
     where modulo = 'manutencao' and caminho = 'equipamentos'
       and dados->>'nome' = r.nome
       and coalesce(dados->>'linha', '') in ('UTIL', 'L2', r.setor)
       and (dados->>'linha' <> 'L2' or r.nome = 'Robô Paletizador');
  end loop;

  -- os que faltavam: cadastra (sem TAG, tipo "Outro"), se ainda não houver um com o mesmo nome
  for r in
    select * from (values
      ('Empilhadeiras', 'PALET', 9), ('Paleteiras', 'PALET', 10),
      ('Gerador de Ozônio', 'ENV', 2), ('Respiradores', 'ENV', 3), ('Ecobrisa', 'ENV', 4), ('Reservatórios de água', 'ENV', 5)
    ) as v(nome, setor, ordem)
  loop
    if not exists (select 1 from public.modulo_docs where modulo = 'manutencao' and caminho = 'equipamentos' and lower(dados->>'nome') = lower(r.nome)) then
      insert into public.modulo_docs (modulo, caminho, id, dados)
      values ('manutencao', 'equipamentos', 'set' || substr(md5(r.nome || clock_timestamp()::text), 1, 13),
        jsonb_build_object('nome', r.nome, 'linha', r.setor, 'tag', '', 'tipo', 'Outro', 'fabricante', '', 'modelo', '', 'capacidade', '',
          'local', '', 'criticidade', '', 'obs', '', 'ativo', true, 'ordem', r.ordem, 'criadoEm', agora, 'atualizadoEm', agora,
          'origem', 'Setorização do Geral (17/11/2026)'));
    end if;
  end loop;

  -- as fichas acompanham o setor do equipamento
  update public.modulo_docs f
     set dados = f.dados || jsonb_build_object('linha', e.dados->>'linha', 'atualizadoEm', agora), atualizado_em = now()
    from public.modulo_docs e
   where f.modulo = 'manutencao' and f.caminho = 'fichas'
     and e.modulo = 'manutencao' and e.caminho = 'equipamentos' and e.id = f.dados->>'equipId'
     and e.dados->>'linha' in ('COMP', 'RESAR', 'PALET', 'ENV')
     and coalesce(f.dados->>'linha', '') <> e.dados->>'linha';
end $$;
