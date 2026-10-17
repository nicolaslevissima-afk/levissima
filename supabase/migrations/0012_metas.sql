-- LEVÍSSIMA · 0012: plano de metas de produção (aba Metas), aprovado pelo Nicolas em 17/10/2026.
--
-- Coleção nova na tabela "docs":
--   metas   'plano' (versões das metas e pesos; velocidade nominal das linhas), 'trofeus' (sala de troféus),
--           'mes-AAAA-MM' (lançamentos do mês: segurança, SAC, preventiva e histórico), 'turno-*' (apontamentos
--           de turno para o OEE) e 'resumo-AAAA-MM' (resultado do mês que o escritório publica para os setores)
--
-- Regras (somam com as que já existem; nenhuma regra antiga muda):
--   1. lê: senha mestre, equipe e setores da fábrica (motorista e força de vendas não);
--   2. grava: senha mestre e equipe; os setores só gravam apontamentos de turno (turno-*, tipo "turno");
--   3. plano e troféus: só a senha mestre grava;
--   4. apaga: só a senha mestre.

do $$
begin
  -- quem pode mexer na coleção (restritiva: tira motorista e representante)
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_quem_0012') then
    create policy "metas_quem_0012" on public.docs as restrictive for all to authenticated
      using (colecao <> 'metas' or (select public.papel_atual()) in ('mestre', 'equipe', 'setor'))
      with check (colecao <> 'metas' or (select public.papel_atual()) in ('mestre', 'equipe', 'setor'));
  end if;
  -- setores: leem as metas (permissiva; os setores não têm outra regra de leitura na tabela docs)
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_setor_le_0012') then
    create policy "metas_setor_le_0012" on public.docs for select to authenticated
      using (colecao = 'metas' and (select public.papel_atual()) = 'setor');
  end if;
  -- setores: gravam e corrigem só apontamentos de turno
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_setor_grava_0012') then
    create policy "metas_setor_grava_0012" on public.docs for insert to authenticated
      with check (colecao = 'metas' and (select public.papel_atual()) = 'setor' and id like 'turno-%' and data ->> 'tipo' = 'turno');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_setor_altera_0012') then
    create policy "metas_setor_altera_0012" on public.docs for update to authenticated
      using (colecao = 'metas' and (select public.papel_atual()) = 'setor' and id like 'turno-%')
      with check (colecao = 'metas' and (select public.papel_atual()) = 'setor' and id like 'turno-%' and data ->> 'tipo' = 'turno');
  end if;
  -- plano e troféus: só a senha mestre
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_plano_grava_0012') then
    create policy "metas_plano_grava_0012" on public.docs as restrictive for insert to authenticated
      with check (colecao <> 'metas' or id not in ('plano', 'trofeus') or (select public.papel_atual()) = 'mestre');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_plano_altera_0012') then
    create policy "metas_plano_altera_0012" on public.docs as restrictive for update to authenticated
      using (colecao <> 'metas' or id not in ('plano', 'trofeus') or (select public.papel_atual()) = 'mestre')
      with check (colecao <> 'metas' or id not in ('plano', 'trofeus') or (select public.papel_atual()) = 'mestre');
  end if;
  -- apagar: só a senha mestre
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'docs' and policyname = 'metas_apaga_0012') then
    create policy "metas_apaga_0012" on public.docs as restrictive for delete to authenticated
      using (colecao <> 'metas' or (select public.papel_atual()) = 'mestre');
  end if;
end $$;
