-- 0031 (23/10/2026): o "só inclui" das abas do app não vale nos módulos da fábrica.
-- Quem tem todas as abas marcadas como "só inclui" (ou "só visualiza" + "só inclui") recebe so_inclui no login (0021) e o
-- banco não deixava alterar nem apagar NADA — nem nos módulos (Manutenção, Empilhadeiras…), onde o nível é o do
-- próprio módulo (usar ou gerir). Ex.: o técnico de manutenção não conseguia importar a ficha de preventiva em planilha
-- (a importação atualiza as tarefas do plano) nem registrar o que atualiza uma tarefa.
-- Agora, nos módulos (tabela modulo_docs e fotos/documentos dos módulos), o "só inclui" segura só a diretoria
-- (papel mestre com so_inclui). Nas abas do app (tabela docs) nada muda. As regras da 0014 são ajustadas no lugar.
alter policy "so_inclui_nao_altera_0014" on public.modulo_docs
  using (not ((select public.so_inclui()) and (select public.papel_atual()) = 'mestre') or (caminho = 'config' and id = 'contador'))
  with check (not ((select public.so_inclui()) and (select public.papel_atual()) = 'mestre') or (caminho = 'config' and id = 'contador'));
alter policy "so_inclui_nao_apaga_0014" on public.modulo_docs
  using (not ((select public.so_inclui()) and (select public.papel_atual()) = 'mestre'));
alter policy "so-inclui: nao altera" on storage.objects
  using (not (select public.so_inclui()) or (bucket_id in ('modulos-fotos', 'modulos-docs') and (select public.papel_atual()) <> 'mestre'))
  with check (not (select public.so_inclui()) or (bucket_id in ('modulos-fotos', 'modulos-docs') and (select public.papel_atual()) <> 'mestre'));
alter policy "so-inclui: nao apaga" on storage.objects
  using (not (select public.so_inclui()) or (bucket_id in ('modulos-fotos', 'modulos-docs') and (select public.papel_atual()) <> 'mestre'));
