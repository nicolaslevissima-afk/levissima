-- LEVÍSSIMA · 0061: chamados (TI e manutenção predial) com acesso "só inclui" (pedido de 23/11/2026).
--
-- O Pedro atende os chamados de TI (equipe.atendeTi), mas o acesso dele tem todas as abas marcadas como "só inclui"
-- (so_inclui no login). A regra "so_inclui_nao_altera_0014" barrava qualquer alteração, então ele não conseguia assumir
-- nem atualizar os chamados. Agora a regra deixa alterar os chamados que a pessoa vê: quem atende a área (TI ou
-- predial) e quem abriu o chamado. O que cada um pode mudar continua sendo conferido pelo gatilho docs_chamado_0045
-- (quem abriu só comenta, cancela o aberto e confirma ou reabre o resolvido) e apagar continua só com a senha mestre.
-- A exceção das ordens de compra (0058) continua.

alter policy "so_inclui_nao_altera_0014" on public.docs
  using (not (select public.so_inclui())
         or (colecao = 'compras-ordens' and (select public.papel_atual()) = 'equipe')
         or (colecao = 'chamados' and public.chamado_visivel_0045(data)))
  with check (not (select public.so_inclui())
         or (colecao = 'compras-ordens' and (select public.papel_atual()) = 'equipe')
         or (colecao = 'chamados' and public.chamado_visivel_0045(data)));
